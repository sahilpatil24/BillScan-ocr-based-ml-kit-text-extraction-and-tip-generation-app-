import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:pdfx/pdfx.dart';
import 'package:path_provider/path_provider.dart';

void main() => runApp(const BillScanApp());

// ════════════════════════════════════════════════════════════════════════════
//  APP
// ════════════════════════════════════════════════════════════════════════════

class BillScanApp extends StatelessWidget {
  const BillScanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BillScan',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0A14),
        colorScheme: const ColorScheme.dark(
          primary:   Color(0xFF4ECDC4),
          secondary: Color(0xFFFF6B6B),
          surface:   Color(0xFF13131F),
        ),
      ),
      home: const BillScanPage(),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  DATA MODELS
// ════════════════════════════════════════════════════════════════════════════

enum InsightType { charge, tax, warning, tip, info }

class BillInsight {
  final String title;
  final String value;
  final InsightType type;
  final String? detail;
  const BillInsight({
    required this.title,
    required this.value,
    required this.type,
    this.detail,
  });
}

class BillResult {
  final String billType;
  final String? totalAmount;
  final String? dueDate;
  final String rawText;
  final String extractionMethod;
  final List<BillInsight> charges;
  final List<BillInsight> taxes;
  final List<BillInsight> warnings;
  final List<BillInsight> tips;

  const BillResult({
    required this.billType,
    this.totalAmount,
    this.dueDate,
    required this.rawText,
    required this.extractionMethod,
    required this.charges,
    required this.taxes,
    required this.warnings,
    required this.tips,
  });
}

// ════════════════════════════════════════════════════════════════════════════
//  PDF EXTRACTOR  — 2-tier fallback
//
//  Tier 1 : pdfx built-in text extraction  (fast, works on text-based PDFs)
//  Tier 2 : pdfx render → PNG → ML Kit OCR (works on image-based PDFs)
//  Tier 3 : same as Tier 2 but at 4× scale  (narrow/tiny PDFs like 2-inch receipts)
// ════════════════════════════════════════════════════════════════════════════

class PdfExtractor {
  final _mlKit = TextRecognizer(script: TextRecognitionScript.latin);

  Future<({String text, String method})> extract(
      String pdfPath,
      void Function(String) onProgress,
      ) async {

    // ── Tier 1 : render at 2× → ML Kit OCR ───────────────────────────────
    onProgress('Rendering pages for OCR…');
    final t1 = await _renderAndOcr(pdfPath, scale: 2.0, onProgress: onProgress);
    if (t1 != null && t1.length > 40) {
      return (text: t1, method: 'ML Kit OCR');
    }

    // ── Tier 2 : render at 4× → ML Kit  (narrow / tiny PDFs) ────────────
    onProgress('Retrying at higher resolution…');
    final t2 = await _renderAndOcr(pdfPath, scale: 4.0, onProgress: onProgress);
    if (t2 != null && t2.length > 20) {
      return (text: t2, method: 'ML Kit OCR (Hi-Res)');
    }

    throw Exception(
      'Could not extract text.\n'
          'The PDF may be password-protected or heavily compressed.',
    );
  }

  Future<String?> _renderAndOcr(
      String pdfPath, {
        required double scale,
        required void Function(String) onProgress,
      }) async {
    PdfDocument? doc;
    try {
      doc = await PdfDocument.openFile(pdfPath);
      final total = doc.pagesCount;
      final buf   = StringBuffer();
      final tmp   = await getTemporaryDirectory();

      for (int i = 1; i <= total; i++) {
        onProgress('OCR page $i / $total…');
        PdfPage? page;
        try {
          page = await doc.getPage(i);

          final rawW   = page.width  * scale;
          final rawH   = page.height * scale;
          const maxDim = 3500.0;
          const minDim =  800.0;
          final longest = max(rawW, rawH);
          final factor  = longest > maxDim
              ? maxDim / longest
              : longest < minDim
              ? minDim / longest
              : 1.0;
          final rW = (rawW * factor).clamp(minDim, maxDim);
          final rH = (rawH * factor).clamp(minDim, maxDim);

          final img = await page.render(
            width:           rW,
            height:          rH,
            format:          PdfPageImageFormat.png,
            backgroundColor: '#FFFFFF',
          );

          await page.close();
          page = null;

          if (img == null || img.bytes.isEmpty) continue;

          final imgFile = File('${tmp.path}/ocr_${i}_${scale.toInt()}.png');
          await imgFile.writeAsBytes(img.bytes);

          final recognized = await _mlKit.processImage(
            InputImage.fromFilePath(imgFile.path),
          );
          buf.writeln(recognized.text);

          try { await imgFile.delete(); } catch (_) {}
        } catch (_) {
          try { await page?.close(); } catch (_) {}
        }
      }

      return buf.toString().trim();
    } catch (_) {
      return null;
    } finally {
      try { await doc?.close(); } catch (_) {}
    }
  }

  void dispose() => _mlKit.close();
}

// ════════════════════════════════════════════════════════════════════════════
//  BILL PARSER  — pure regex, zero API calls
// ════════════════════════════════════════════════════════════════════════════

class _Tip {
  final String title;
  final String detail;
  const _Tip(this.title, this.detail);
}

class BillParser {

  // ── Amount patterns ───────────────────────────────────────────────────────

  // "Label : ₹1,234.00"  or  "Label  $1,234.00"  (colon optional)
  static final _labelAmtPat = RegExp(
    r'([\w][\w\s\/\-\(\)]{1,55}?)\s*[:\-]?\s*'
    r'(?:Rs\.?|INR|₹|\$|€|£|AUD\s*\$?)\s*'
    r'(\d{1,3}(?:[,\d{3}]*)?(?:\.\d{1,2})?)',
    caseSensitive: false,
  );

  // Any standalone currency amount (for fallback total detection)
  static final _anyAmtPat = RegExp(
    r'(?:Rs\.?|INR|₹|\$|€|£|AUD\s*\$?)\s*'
    r'(\d{1,3}(?:[,\d{3}]*)?(?:\.\d{1,2})?)',
    caseSensitive: false,
  );

  // Total-like labels
  static final _totalPat = RegExp(
    r'(?:total\s*(?:amount|due|payable)?|amount\s*(?:due|payable)|'
    r'net\s*(?:amount|payable)|grand\s*total|balance\s*due|'
    r'amount\s*to\s*pay|amount\s*due)\s*[:\s]*'
    r'(?:Rs\.?|INR|₹|\$|€|£|AUD\s*\$?)?\s*(\d[\d,\.]+)',
    caseSensitive: false,
  );

  // Due date
  static final _duePat = RegExp(
    r'(?:due\s*(?:date|by|on)?|payment\s*date|pay\s*by|last\s*date)'
    r'\s*[:\-]?\s*([^\n]{3,30})',
    caseSensitive: false,
  );

  // Tax labels
  static final _taxPat = RegExp(
    r'\b(IGST|CGST|SGST|GST|VAT|service\s*tax|cess)\s*'
    r'(?:at\s*\d+\.?\d*\s*%)?\s*[:\-]?\s*'
    r'(?:Rs\.?|INR|₹|\$|€|£)?\s*(\d[\d,\.]+)?',
    caseSensitive: false,
  );

  // Late fee
  static final _latePat = RegExp(
    r'(?:late\s*(?:fee|charge|payment)|overdue|penalty)\s*[:\-]?\s*'
    r'(?:Rs\.?|INR|₹|\$)?\s*(\d[\d,\.]+)?',
    caseSensitive: false,
  );

  // Surcharge / service fee
  static final _surchargePat = RegExp(
    r'(?:surcharge|convenience\s*fee|processing\s*fee|'
    r'service\s*(?:fee|charge)|connection\s*charge|fixed\s*charge|rental)'
    r'\s*[:\-]?\s*(?:Rs\.?|INR|₹|\$)?\s*(\d[\d,\.]+)?',
    caseSensitive: false,
  );

  // Generic date
  static final _datePat = RegExp(
    r'\b(\d{1,2}[\/\-\.]\d{1,2}[\/\-\.]\d{2,4}|'
    r'\d{4}[\/\-\.]\d{1,2}[\/\-\.]\d{1,2}|'
    r'(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)'
    r'[a-z]*[\s\-\.]\d{1,2}[\s\-,\.]\d{2,4})\b',
    caseSensitive: false,
  );

  // Labels too generic to show as individual charges
  static const _skipLabels = {
    'qty','price','amt','amount','sn','no','s/no','item','description',
    'unit','rate','total','subtotal','sub total','comment','comments',
    'bill to','ship to','terms','date','ref','page','email','web','tel',
    'fax','phone','address','name',
  };

  // ── Bill type keywords ────────────────────────────────────────────────────

  static const _typeKw = <String, List<String>>{
    'Electricity': ['kwh','units consumed','electricity','power supply','energy bill','watt','msedcl','bescom','tneb'],
    'Internet':    ['broadband','internet','data usage','mbps','gbps','fiber','airtel fiber','jio fiber','bsnl','act fibernet'],
    'Mobile':      ['mobile','recharge','call charges','roaming','prepaid','postpaid','airtel','vodafone','jio mobile'],
    'Water':       ['water supply','sewage','water consumption','kl','municipal water','jal board'],
    'Gas':         ['lpg','cylinder','png','piped gas','mgl','igl','natural gas'],
    'Credit Card': ['credit card','minimum due','outstanding balance','cash advance','credit limit'],
    'DTH/Cable':   ['dth','cable tv','set-top','channel pack','tatasky','dish tv'],
    'Invoice':     ['tax invoice','professional services','accounting','bookkeeping','consulting','invoice'],
    'Grocery':     ['orange powder','walnuts','cheese','rose water','grocery','retail','supermarket'],
  };

  // ── Tips library ──────────────────────────────────────────────────────────

  static const _tips = <String, List<_Tip>>{
    'Electricity': [
      _Tip('Switch to LED bulbs',         'LEDs use 70–80% less power than incandescent bulbs.'),
      _Tip('Run appliances off-peak',      'Schedule washing machines & geysers at night to reduce peak-hour charges.'),
      _Tip('Stay in lower tariff slab',    'Saving a few units can drop you to a cheaper consumption slab.'),
      _Tip('Unplug standby devices',       'Standby "vampire" power can be up to 10% of your bill.'),
    ],
    'Internet': [
      _Tip('Downgrade speed if unused',   'Most home use doesn\'t need max speed — save ₹200–500/month.'),
      _Tip('Switch to annual plan',        'Annual plans are typically 15–20% cheaper than monthly billing.'),
      _Tip('Bundle with OTT',             'Some ISPs include free Netflix/Prime — check if yours qualifies.'),
    ],
    'Mobile': [
      _Tip('Switch to prepaid',            'Same data/calls at 20–30% lower cost vs postpaid.'),
      _Tip('Use Wi-Fi calling at home',    'Saves on call minutes — WhatsApp & Wi-Fi calling are free.'),
      _Tip('Disable international roaming','Roaming is up to 10× normal rates — use local SIM abroad.'),
    ],
    'Credit Card': [
      _Tip('Pay full balance every month', 'Carrying a balance attracts 36–48% p.a. interest.'),
      _Tip('Pay before due date',          'Late fees of ₹500–1200 plus interest damage your credit score.'),
      _Tip('Avoid cash advances',          '2.5% upfront fee + interest from day one — use UPI instead.'),
      _Tip('Redeem reward points',         'Most points expire in 1–2 years; apply them to reduce outstanding.'),
    ],
    'Invoice': [
      _Tip('Check for early-pay discount', 'Many vendors offer 1–2% off for settling before due date.'),
      _Tip('Negotiate payment terms',      'Net-60 or Net-90 terms improve your cash flow significantly.'),
      _Tip('Verify every line item',       'Cross-check charges against the agreed scope of work.'),
      _Tip('Archive for tax purposes',     'Keep invoices for 7 years for GST / income-tax audits.'),
    ],
    'Grocery': [
      _Tip('Verify GST slabs',             'Essential goods are 0–5% GST — check you\'re not overcharged.'),
      _Tip('Buy staples in bulk',          'Bulk purchases often attract quantity discounts.'),
      _Tip('Compare unit prices',          'Larger packs are not always cheaper per unit — always check.'),
    ],
    'Gas': [
      _Tip('Use a pressure cooker',        'Reduces cooking time and gas use by up to 50%.'),
      _Tip('Keep burners clean',           'Clogged burners waste 15–20% more gas.'),
      _Tip('Verify DBT subsidy credit',    'Ensure your PAHAL subsidy is credited to your bank account.'),
    ],
    'Water': [
      _Tip('Fix leaks promptly',           'A dripping tap wastes ~15 litres/day.'),
      _Tip('Install low-flow aerators',    'Cuts tap flow 30–50% with no noticeable difference in use.'),
    ],
  };

  static const _genericTips = [
    _Tip('Go paperless',             'E-bills are free; paper bill charges add ₹50–200/year.'),
    _Tip('Pay 2–3 days early',       'Avoids late fees even if bank transfers take a day to clear.'),
    _Tip('Review your plan annually','Providers update offerings — you may qualify for a better deal.'),
    _Tip('Check for duplicate items','Billing errors occur more often than you might expect.'),
  ];

  // ── Main parse ────────────────────────────────────────────────────────────

  static BillResult parse(String text, String method) {
    final lower = text.toLowerCase();

    // 1. Detect bill type
    var billType = 'General';
    var maxHits  = 0;
    _typeKw.forEach((type, kws) {
      final hits = kws.where(lower.contains).length;
      if (hits > maxHits) { maxHits = hits; billType = type; }
    });

    // 2. Total amount
    String? total;
    final tm = _totalPat.firstMatch(text);
    if (tm != null) {
      total = _fmt(tm.group(1)!, text);
    } else {
      final amounts = _anyAmtPat.allMatches(text)
          .map((m) => double.tryParse(m.group(1)!.replaceAll(',', '')) ?? 0)
          .toList()
        ..sort((a, b) => b.compareTo(a));
      if (amounts.isNotEmpty) total = _fmt(amounts.first.toStringAsFixed(2), text);
    }

    // 3. Due date
    String? dueDate;
    final dm = _duePat.firstMatch(text);
    if (dm != null) dueDate = dm.group(1)?.trim();

    // 4. Charges
    final charges   = <BillInsight>[];
    final seenCharge = <String>{};
    for (final m in _labelAmtPat.allMatches(text)) {
      final lbl = _clean(m.group(1) ?? '');
      final amt = m.group(2) ?? '';
      if (lbl.length < 2) continue;
      if (_skipLabels.contains(lbl.toLowerCase())) continue;
      if (_isTaxLbl(lbl)) continue;
      if (_isTotalLbl(lbl)) continue;
      if (!seenCharge.add(lbl.toLowerCase())) continue;
      charges.add(BillInsight(title: lbl, value: _fmt(amt, text), type: InsightType.charge));
    }

    // 5. Taxes
    final taxes   = <BillInsight>[];
    final seenTax = <String>{};
    for (final m in _taxPat.allMatches(text)) {
      final lbl = _taxLbl(m.group(0) ?? '');
      if (!seenTax.add(lbl.toLowerCase())) continue;
      final amt = m.group(2);
      taxes.add(BillInsight(
        title:  lbl,
        value:  amt != null ? _fmt(amt, text) : 'Applicable',
        type:   InsightType.tax,
        detail: 'Government levy on taxable goods/services',
      ));
    }

    // 6. Warnings
    final warnings = <BillInsight>[];
    if (_latePat.hasMatch(lower)) {
      final m = _latePat.firstMatch(text);
      warnings.add(BillInsight(
        title:  'Late Payment Fee',
        value:  m?.group(1) != null ? _fmt(m!.group(1)!, text) : 'Applicable',
        type:   InsightType.warning,
        detail: 'Charged if payment is not made by due date.',
      ));
    }
    if (_surchargePat.hasMatch(lower)) {
      final m = _surchargePat.firstMatch(text);
      warnings.add(BillInsight(
        title:  'Surcharge / Service Fee',
        value:  m?.group(1) != null ? _fmt(m!.group(1)!, text) : 'Applicable',
        type:   InsightType.warning,
        detail: 'Extra fee on top of your base charge.',
      ));
    }
    if (lower.contains('overdue') || lower.contains('past due') || lower.contains('unpaid')) {
      warnings.add(const BillInsight(
        title:  '⚠️ Unpaid / Overdue',
        value:  'Action needed',
        type:   InsightType.warning,
        detail: 'This bill is marked unpaid. Pay immediately to avoid penalties.',
      ));
    }
    if (dueDate == null) {
      final dates = _datePat.allMatches(text)
          .map((m) => m.group(0)!).toSet().take(3).toList();
      if (dates.isNotEmpty) {
        warnings.add(BillInsight(
          title:  'Dates found in document',
          value:  dates.join(', '),
          type:   InsightType.info,
          detail: 'Verify which date is your payment due date.',
        ));
      }
    }

    // 7. Tips
    final tipRules = [...(_tips[billType] ?? []), ..._genericTips];
    final tips = tipRules.map((r) => BillInsight(
      title:  r.title,
      value:  '💡',
      type:   InsightType.tip,
      detail: r.detail,
    )).toList();

    return BillResult(
      billType:          billType,
      totalAmount:       total,
      dueDate:           dueDate,
      rawText:           text,
      extractionMethod:  method,
      charges:           charges,
      taxes:             taxes,
      warnings:          warnings,
      tips:              tips,
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static String _fmt(String num, String fullText) {
    final t = fullText;
    if (t.contains('₹') || t.toLowerCase().contains('inr')) return '₹ $num';
    if (t.contains(r'$'))                                    return '\$ $num';
    if (t.contains('€'))                                     return '€ $num';
    if (t.contains('£'))                                     return '£ $num';
    return '₹ $num';
  }

  static bool _isTaxLbl(String l) {
    final lo = l.toLowerCase();
    return ['gst','igst','cgst','sgst','vat','tax','cess'].any(lo.contains);
  }

  static bool _isTotalLbl(String l) {
    final lo = l.toLowerCase();
    return ['total','subtotal','sub total','grand total','amount due',
      'amount payable','balance due','net amount','amount paid'].any(lo.contains);
  }

  static String _clean(String s) =>
      s.replaceAll(RegExp(r'[\:\-\s]+$'), '').replaceAll(RegExp(r'\s+'), ' ').trim();

  static String _taxLbl(String raw) {
    final u = raw.toUpperCase();
    if (u.contains('IGST')) {
      final pct = RegExp(r'IGST\s*(?:AT\s*)?(\d+\.?\d*)').firstMatch(u);
      return pct != null ? 'IGST @ ${pct.group(1)}%' : 'IGST';
    }
    if (u.contains('CGST')) return 'CGST';
    if (u.contains('SGST')) return 'SGST';
    if (u.contains('GST'))  return 'GST';
    if (u.contains('VAT'))  return 'VAT';
    if (u.contains('SERVICE TAX')) return 'Service Tax';
    if (u.contains('CESS')) return 'Cess';
    return 'Tax';
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  MAIN PAGE
// ════════════════════════════════════════════════════════════════════════════

class BillScanPage extends StatefulWidget {
  const BillScanPage({super.key});
  @override
  State<BillScanPage> createState() => _BillScanPageState();
}

class _BillScanPageState extends State<BillScanPage> with TickerProviderStateMixin {
  String?    _fileName;
  BillResult? _result;
  bool       _isLoading = false;
  String     _loadingStep = '';
  String?    _error;
  int        _activeTab = 0;
  bool       _showRaw   = false;

  late AnimationController _shimmerCtrl;
  late AnimationController _fadeCtrl;
  late Animation<double>   _fadeAnim;

  final _extractor = PdfExtractor();

  // ── colour helpers (no deprecated withOpacity) ───────────────────────────
  static Color _o(Color c, double opacity) =>
      c.withValues(alpha: opacity);

  @override
  void initState() {
    super.initState();
    _shimmerCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 2))..repeat();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _shimmerCtrl.dispose();
    _fadeCtrl.dispose();
    _extractor.dispose();
    super.dispose();
  }

  // ── Core ──────────────────────────────────────────────────────────────────

  Future<void> _pickAndScan() async {
    setState(() { _error = null; _result = null; _showRaw = false; });

    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (picked == null || picked.files.single.path == null) return;

      setState(() {
        _fileName    = picked.files.single.name;
        _isLoading   = true;
        _loadingStep = 'Starting…';
      });

      final (:text, :method) = await _extractor.extract(
        picked.files.single.path!,
            (msg) => setState(() => _loadingStep = msg),
      );

      setState(() => _loadingStep = 'Parsing bill…');
      final result = BillParser.parse(text, method);

      setState(() {
        _result     = result;
        _isLoading  = false;
        _activeTab  = 0;
      });
      _fadeCtrl.forward(from: 0);
    } catch (e) {
      setState(() { _isLoading = false; _error = e.toString(); });
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A14),
      body: SafeArea(
        child: Column(children: [
          _buildHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Column(children: [
                const SizedBox(height: 20),
                _buildUploadBtn(),
                if (_isLoading) ...[const SizedBox(height: 32), _buildLoader()],
                if (_error != null) ...[const SizedBox(height: 20), _buildErrorCard()],
                if (_result != null) ...[
                  const SizedBox(height: 24),
                  FadeTransition(opacity: _fadeAnim, child: _buildResults()),
                ],
                const SizedBox(height: 48),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A14),
        border: Border(bottom: BorderSide(color: _o(Colors.white, 0.06))),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF4ECDC4), Color(0xFF2BAE9F)]),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.document_scanner_rounded, color: Colors.white, size: 20),
        ),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('BillScan',
              style: TextStyle(color: Colors.white, fontSize: 18,
                  fontWeight: FontWeight.w800, letterSpacing: -0.5)),
          Text('ML Kit OCR  •  Regex Parser  •  100% Offline',
              style: TextStyle(color: _o(Colors.white, 0.35), fontSize: 10.5)),
        ]),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: _o(const Color(0xFF4ECDC4), 0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _o(const Color(0xFF4ECDC4), 0.3)),
          ),
          child: const Text('FREE',
              style: TextStyle(color: Color(0xFF4ECDC4), fontSize: 11,
                  fontWeight: FontWeight.w800, letterSpacing: 1)),
        ),
      ]),
    );
  }

  // ── Upload button ─────────────────────────────────────────────────────────

  Widget _buildUploadBtn() {
    final hasResult = _result != null;
    return GestureDetector(
      onTap: _isLoading ? null : _pickAndScan,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
        decoration: BoxDecoration(
          color: const Color(0xFF13131F),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: hasResult
                ? _o(const Color(0xFF4ECDC4), 0.4)
                : _o(Colors.white, 0.09),
            width: 1.5,
          ),
        ),
        child: Column(children: [
          Icon(
            hasResult ? Icons.check_circle_rounded : Icons.upload_file_rounded,
            color: hasResult ? const Color(0xFF4ECDC4) : _o(Colors.white, 0.38),
            size: 38,
          ),
          const SizedBox(height: 10),
          Text(
            _fileName ?? 'Tap to select a PDF bill',
            style: TextStyle(
              color: _o(Colors.white, _fileName != null ? 0.9 : 0.45),
              fontWeight: FontWeight.w600, fontSize: 15,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            hasResult
                ? 'Tap to scan a different PDF'
                : 'Electricity • Invoice • Receipt • Credit Card • Any bill',
            style: TextStyle(color: _o(Colors.white, 0.28), fontSize: 12),
          ),
        ]),
      ),
    );
  }

  // ── Loader ────────────────────────────────────────────────────────────────

  Widget _buildLoader() {
    return AnimatedBuilder(
      animation: _shimmerCtrl,
      builder: (_, __) => Column(children: [
        SizedBox(
          width: 48, height: 48,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            color: Color.lerp(
              const Color(0xFF4ECDC4),
              const Color(0xFF2BAE9F),
              _shimmerCtrl.value,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(_loadingStep,
            style: TextStyle(color: _o(Colors.white, 0.75),
                fontSize: 14, fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        Text('No internet required',
            style: TextStyle(color: _o(Colors.white, 0.3), fontSize: 12)),
      ]),
    );
  }

  // ── Error card ────────────────────────────────────────────────────────────

  Widget _buildErrorCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _o(const Color(0xFFFF6B6B), 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _o(const Color(0xFFFF6B6B), 0.3)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.error_outline_rounded, color: Color(0xFFFF6B6B)),
        const SizedBox(width: 10),
        Expanded(child: Text(_error!,
            style: const TextStyle(color: Color(0xFFFFAAAA), fontSize: 13, height: 1.4))),
      ]),
    );
  }

  // ── Results ───────────────────────────────────────────────────────────────

  Widget _buildResults() {
    final r = _result!;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _buildSummary(r),
      const SizedBox(height: 20),
      _buildTabBar(r),
      const SizedBox(height: 16),
      _buildTabContent(r),
      const SizedBox(height: 16),
      _buildRawToggle(r),
    ]);
  }

  // ── Summary banner ────────────────────────────────────────────────────────

  Widget _buildSummary(BillResult r) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFF142020), Color(0xFF111E1E)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _o(const Color(0xFF4ECDC4), 0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Badges row
        Row(children: [
          _badge(r.billType.toUpperCase(), const Color(0xFF4ECDC4), 0.12, 1.2),
          const SizedBox(width: 8),
          _badge(r.extractionMethod, Colors.white, 0.06, 0),
        ]),
        const SizedBox(height: 12),
        // Amount + due date
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Total Amount',
                style: TextStyle(color: _o(Colors.white, 0.38), fontSize: 12)),
            Text(
              r.totalAmount ?? 'Not detected',
              style: TextStyle(
                color: r.totalAmount != null ? Colors.white : _o(Colors.white, 0.3),
                fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -1,
              ),
            ),
          ])),
          if (r.dueDate != null)
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('Due Date',
                  style: TextStyle(color: _o(Colors.white, 0.38), fontSize: 11)),
              const SizedBox(height: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: _o(const Color(0xFFFF6B6B), 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _o(const Color(0xFFFF6B6B), 0.3)),
                ),
                child: Text(r.dueDate!,
                    style: const TextStyle(color: Color(0xFFFF9999),
                        fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ]),
        ]),
      ]),
    );
  }

  Widget _badge(String label, Color c, double bgAlpha, double letterSpacing) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _o(c, bgAlpha),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          style: TextStyle(
              color: _o(c, bgAlpha > 0.1 ? 1.0 : 0.45),
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: letterSpacing)),
    );
  }

  // ── Tab bar ───────────────────────────────────────────────────────────────

  static const _tabLabels = ['Charges', 'Taxes', 'Warnings', 'Tips'];
  static const _tabIcons  = [
    Icons.receipt_long_rounded,
    Icons.account_balance_rounded,
    Icons.warning_amber_rounded,
    Icons.lightbulb_outline_rounded,
  ];
  static const _tabColors = [
    Color(0xFF74C0FC),
    Color(0xFFFFD43B),
    Color(0xFFFF6B6B),
    Color(0xFF51CF66),
  ];

  Widget _buildTabBar(BillResult r) {
    final counts = [r.charges.length, r.taxes.length, r.warnings.length, r.tips.length];
    return Row(
      children: List.generate(_tabLabels.length, (i) {
        final active = _activeTab == i;
        final col    = _tabColors[i];
        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _activeTab = i),
            child: Container(
              margin: EdgeInsets.only(right: i < _tabLabels.length - 1 ? 8 : 0),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: active ? _o(col, 0.12) : const Color(0xFF13131F),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: active ? _o(col, 0.45) : _o(Colors.white, 0.07)),
              ),
              child: Column(children: [
                Icon(_tabIcons[i],
                    color: active ? col : _o(Colors.white, 0.24), size: 16),
                const SizedBox(height: 3),
                Text(_tabLabels[i],
                    style: TextStyle(
                        color: active ? col : _o(Colors.white, 0.24),
                        fontSize: 9.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text('${counts[i]}',
                    style: TextStyle(
                        color: active ? _o(col, 0.7) : _o(Colors.white, 0.15),
                        fontSize: 9, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        );
      }),
    );
  }

  // ── Tab content ───────────────────────────────────────────────────────────

  Widget _buildTabContent(BillResult r) {
    final lists  = [r.charges, r.taxes, r.warnings, r.tips];
    final items  = lists[_activeTab];
    final col    = _tabColors[_activeTab];
    const empties = [
      'No itemised charges detected.\nCheck the raw text section below.',
      'No tax lines detected.',
      '✅  No warnings — bill looks clean!',
      'No tips available.',
    ];
    if (items.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
            color: const Color(0xFF13131F),
            borderRadius: BorderRadius.circular(16)),
        child: Center(
          child: Text(empties[_activeTab],
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: _o(Colors.white, 0.38), fontSize: 13, height: 1.5)),
        ),
      );
    }
    return Column(children: items.map((e) => _tile(e, col)).toList());
  }

  Widget _tile(BillInsight ins, Color color) {
    final icon = switch (ins.type) {
      InsightType.charge  => Icons.receipt_rounded,
      InsightType.tax     => Icons.account_balance_rounded,
      InsightType.warning => Icons.warning_amber_rounded,
      InsightType.tip     => Icons.lightbulb_rounded,
      InsightType.info    => Icons.info_rounded,
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _o(color, 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _o(color, 0.14)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
              color: _o(color, 0.14), borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: color, size: 14),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(ins.title,
                    style: const TextStyle(
                        color: Colors.white, fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ),
              Text(ins.value,
                  style: TextStyle(
                      color: color, fontSize: 12,
                      fontWeight: FontWeight.w700)),
            ]),
            if (ins.detail != null) ...[
              const SizedBox(height: 4),
              Text(ins.detail!,
                  style: TextStyle(
                      color: _o(Colors.white, 0.38),
                      fontSize: 12, height: 1.4)),
            ],
          ]),
        ),
      ]),
    );
  }

  // ── Raw text toggle ───────────────────────────────────────────────────────

  Widget _buildRawToggle(BillResult r) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      GestureDetector(
        onTap: () => setState(() => _showRaw = !_showRaw),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF13131F),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _o(Colors.white, 0.07)),
          ),
          child: Row(children: [
            Icon(Icons.code_rounded,
                color: _o(Colors.white, 0.4), size: 16),
            const SizedBox(width: 8),
            Text('Raw extracted text',
                style: TextStyle(color: _o(Colors.white, 0.4), fontSize: 13)),
            const Spacer(),
            Icon(_showRaw ? Icons.expand_less : Icons.expand_more,
                color: _o(Colors.white, 0.38), size: 18),
          ]),
        ),
      ),
      if (_showRaw) ...[
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF0D0D18),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _o(Colors.white, 0.06)),
          ),
          child: SelectableText(
            r.rawText,
            style: TextStyle(
                color: _o(Colors.white, 0.55),
                fontSize: 11.5,
                fontFamily: 'monospace',
                height: 1.5),
          ),
        ),
      ],
    ]);
  }
}