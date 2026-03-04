import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:pdfx/pdfx.dart';
import 'package:path_provider/path_provider.dart';

void main() => runApp(const BillScanApp());

// ════════════════════════════════════════════════════════════
//  APP
// ════════════════════════════════════════════════════════════

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
          primary: Color(0xFF4ECDC4),
          secondary: Color(0xFFFF6B6B),
          surface: Color(0xFF13131F),
        ),
      ),
      home: const BillScanPage(),
    );
  }
}

// ════════════════════════════════════════════════════════════
//  DATA MODELS
// ════════════════════════════════════════════════════════════

enum InsightType { charge, tax, warning, tip, info, date }

class BillInsight {
  final String title;
  final String value;
  final InsightType type;
  final String? detail;
  BillInsight({required this.title, required this.value, required this.type, this.detail});
}

class BillResult {
  final String billType;
  final String? totalAmount;
  final String? dueDate;
  final String rawText;
  final List<BillInsight> charges;
  final List<BillInsight> taxes;
  final List<BillInsight> warnings;
  final List<BillInsight> tips;

  BillResult({
    required this.billType,
    this.totalAmount,
    this.dueDate,
    required this.rawText,
    required this.charges,
    required this.taxes,
    required this.warnings,
    required this.tips,
  });
}

// ════════════════════════════════════════════════════════════
//  RULE-BASED PARSER  (regex, zero external calls)
// ════════════════════════════════════════════════════════════

class BillTipRule {
  final String title;
  final String detail;
  const BillTipRule(this.title, this.detail);
}

class BillParser {
  // ── Patterns ──────────────────────────────────────────────

  static final _totalPat = RegExp(
    r'(?:total\s*(?:amount|due|payable|bill)|amount\s*(?:due|payable)|net\s*(?:amount|payable)|'
    r'grand\s*total|balance\s*due|amount\s*to\s*pay)[:\s]*(?:Rs\.?|INR|₹|\$|€|£)?\s*(\d[\d,\.]+)',
    caseSensitive: false,
  );

  static final _amountLabelPat = RegExp(
    r'([\w][\w\s\/\-]{1,50}?)\s*[:\-]\s*(?:Rs\.?|INR|₹|\$|€|£)\s*(\d[\d,\.]+)',
    caseSensitive: false,
  );

  static final _duePat = RegExp(
    r'(?:due\s*(?:date|by|on)?|payment\s*date|pay\s*by|last\s*date)[:\s]*([^\n]{3,25})',
    caseSensitive: false,
  );

  static final _taxPat = RegExp(
    r'\b(GST|VAT|CGST|SGST|IGST|cess|service\s*tax)[:\s@]*(?:\d+\.?\d*\s*%\s*)?(?:Rs\.?|INR|₹|\$)?\s*(\d[\d,\.]+)?',
    caseSensitive: false,
  );

  static final _lateFeePat = RegExp(
    r'(?:late\s*(?:fee|charge|payment)|overdue|penalty)[:\s]*(?:Rs\.?|INR|₹|\$)?\s*(\d[\d,\.]+)?',
    caseSensitive: false,
  );

  static final _surchargePat = RegExp(
    r'(?:surcharge|convenience\s*fee|processing\s*fee|service\s*(?:fee|charge)|'
    r'connection\s*charge|fixed\s*charge|rental)[:\s]*(?:Rs\.?|INR|₹|\$)?\s*(\d[\d,\.]+)?',
    caseSensitive: false,
  );

  static final _datePat = RegExp(
    r'\b(\d{1,2}[\/\-\.]\d{1,2}[\/\-\.]\d{2,4}|\d{4}[\/\-\.]\d{1,2}[\/\-\.]\d{1,2}|'
    r'(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*[\s\-\.]\d{1,2}[\s\-,\.]\d{4})\b',
    caseSensitive: false,
  );

  static final _amountOnlyPat = RegExp(
    r'(?:Rs\.?|INR|₹|\$|€|£)\s*(\d{1,3}(?:,\d{3})*(?:\.\d{1,2})?)',
    caseSensitive: false,
  );

  // ── Bill types ────────────────────────────────────────────

  static const _typeKeywords = <String, List<String>>{
    'Electricity': ['kwh','units consumed','electricity','power supply','energy bill','watt','msedcl','bescom','tneb','tpddl','discoms'],
    'Internet': ['broadband','internet','data usage','mbps','gbps','wifi','fiber','airtel fiber','jio fiber','bsnl','act fibernet'],
    'Mobile/Phone': ['mobile','recharge','call charges','sms','roaming','prepaid','postpaid','airtel','vodafone','jio','bsnl mobile'],
    'Water': ['water supply','sewage','water consumption','kl','municipal water','jal board'],
    'Gas': ['gas','lpg','cylinder','png','piped gas','mgl','igl','natural gas'],
    'Credit Card': ['credit card','statement','minimum due','outstanding balance','cash advance','credit limit','minimum amount due'],
    'DTH/Cable': ['dth','cable tv','set-top box','subscription','channel pack','tatasky','dish tv','sun direct','airtel dth'],
  };

  // ── Tip library ───────────────────────────────────────────

  static const _tipMap = <String, List<BillTipRule>>{
    'Electricity': [
      BillTipRule('Switch to LED bulbs', 'LEDs consume 70–80% less power than incandescent bulbs.'),
      BillTipRule('Run heavy appliances off-peak', 'Schedule washing machines & geysers at night to reduce peak-hour charges.'),
      BillTipRule('Stay in lower consumption slab', 'Electricity is tiered — saving a few units can drop you to a cheaper slab.'),
      BillTipRule('Unplug standby devices', 'Standby power ("vampire power") can account for up to 10% of your bill.'),
      BillTipRule('Consider solar rooftop', 'Net metering schemes let you sell back excess solar energy to the grid.'),
    ],
    'Internet': [
      BillTipRule('Downgrade speed tier if unused', 'Most home usage doesn\'t need max speed — save ₹200–500/month.'),
      BillTipRule('Switch to annual prepaid plan', 'Annual plans are typically 15–20% cheaper than monthly billing.'),
      BillTipRule('Bundle with OTT services', 'Some ISPs include free Netflix/Prime — check if yours does.'),
      BillTipRule('Avoid data add-on purchases', 'Top-up data packs are 3–5x costlier per GB than your base plan.'),
    ],
    'Mobile/Phone': [
      BillTipRule('Switch to prepaid', 'Same data/calls at 20–30% lower cost compared to postpaid.'),
      BillTipRule('Use Wi-Fi calling at home', 'Saves on call minutes — WhatsApp & native Wi-Fi calling are free.'),
      BillTipRule('Disable international roaming', 'Roaming charges are up to 10x normal rates — use local SIM abroad.'),
      BillTipRule('Audit add-on subscriptions', 'Caller tunes, data boosters, and content packs quietly inflate bills.'),
    ],
    'Water': [
      BillTipRule('Fix leaks promptly', 'A dripping tap wastes ~15 litres/day — significant over a month.'),
      BillTipRule('Install low-flow aerators', 'Reduce tap flow by 30–50% with no noticeable difference in use.'),
      BillTipRule('Harvest rainwater', 'Reduces metered supply dependency for gardening and outdoor use.'),
    ],
    'Gas': [
      BillTipRule('Use a pressure cooker', 'Reduces cooking time and gas consumption by up to 50%.'),
      BillTipRule('Keep burners clean', 'Clogged burners waste 15–20% more gas per meal.'),
      BillTipRule('Verify subsidy credit (DBT)', 'Ensure your PAHAL/DBT subsidy is being credited to your account.'),
    ],
    'Credit Card': [
      BillTipRule('Always pay the full balance', 'Carrying a balance attracts 36–48% p.a. interest — very costly.'),
      BillTipRule('Pay a few days before due date', 'Avoids late fees (₹500–1200) and negative credit score impact.'),
      BillTipRule('Avoid cash advances', '2.5% upfront fee + interest from day one — use UPI/debit instead.'),
      BillTipRule('Redeem reward points before expiry', 'Most points expire in 1–2 years; apply them to reduce outstanding.'),
      BillTipRule('Enable auto-pay for minimum due', 'Prevents accidental missed payments even if you forget.'),
    ],
    'DTH/Cable': [
      BillTipRule('Remove unused channels from pack', 'TRAI rules allow à-la-carte channel selection — pay only for what you watch.'),
      BillTipRule('Switch to annual subscription', 'Annual plans often include 1–2 months free compared to monthly.'),
      BillTipRule('Consider OTT alternatives', 'Streaming services may offer more content at lower total cost.'),
    ],
  };

  static const _genericTips = [
    BillTipRule('Go paperless', 'E-bills are free; paper bill charges can add ₹50–200/year.'),
    BillTipRule('Pay 2–3 days before due date', 'Avoids late fees even if bank transfers take a day to clear.'),
    BillTipRule('Review plans annually', 'Providers update offerings — you may qualify for a better deal.'),
    BillTipRule('Check for duplicate line items', 'Billing errors are more common than expected; scan every charge.'),
  ];

  // ── Main ─────────────────────────────────────────────────

  static BillResult parse(String text) {
    final lower = text.toLowerCase();

    // 1. Bill type
    String billType = 'General';
    int maxHits = 0;
    _typeKeywords.forEach((type, keywords) {
      final hits = keywords.where((k) => lower.contains(k)).length;
      if (hits > maxHits) { maxHits = hits; billType = type; }
    });

    // 2. Total amount
    String? totalAmount;
    final tm = _totalPat.firstMatch(text);
    if (tm != null) {
      totalAmount = '₹ ${tm.group(1)}';
    } else {
      final amounts = _amountOnlyPat.allMatches(text)
          .map((m) => double.tryParse(m.group(1)!.replaceAll(',', '')) ?? 0)
          .toList()
        ..sort((a, b) => b.compareTo(a));
      if (amounts.isNotEmpty) totalAmount = '₹ ${amounts.first.toStringAsFixed(2)}';
    }

    // 3. Due date
    String? dueDate;
    final dm = _duePat.firstMatch(text);
    if (dm != null) dueDate = dm.group(1)?.trim();

    // 4. Charges (labelled amounts, excluding tax labels)
    final charges = <BillInsight>[];
    final seenCharges = <String>{};
    for (final m in _amountLabelPat.allMatches(text)) {
      final lbl = _cleanLabel(m.group(1) ?? '');
      final amt = m.group(2) ?? '';
      if (lbl.length < 3) continue;
      if (_isTaxLabel(lbl)) continue;
      if (!seenCharges.add(lbl.toLowerCase())) continue;
      charges.add(BillInsight(title: lbl, value: '₹ $amt', type: InsightType.charge));
    }

    // 5. Taxes
    final taxes = <BillInsight>[];
    final seenTax = <String>{};
    for (final m in _taxPat.allMatches(text)) {
      final lbl = _taxLabel(m.group(1) ?? '');
      if (!seenTax.add(lbl.toLowerCase())) continue;
      final amt = m.group(2);
      taxes.add(BillInsight(
        title: lbl,
        value: amt != null ? '₹ $amt' : 'Applicable',
        type: InsightType.tax,
        detail: 'Government levy — charged on taxable services',
      ));
    }

    // 6. Warnings
    final warnings = <BillInsight>[];
    if (_lateFeePat.hasMatch(lower)) {
      final m = _lateFeePat.firstMatch(text);
      warnings.add(BillInsight(
        title: 'Late Payment Fee',
        value: m?.group(1) != null ? '₹ ${m!.group(1)}' : 'Applicable',
        type: InsightType.warning,
        detail: 'Will be charged if payment is not made by due date.',
      ));
    }
    if (_surchargePat.hasMatch(lower)) {
      final m = _surchargePat.firstMatch(text);
      warnings.add(BillInsight(
        title: 'Surcharge / Service Fee',
        value: m?.group(1) != null ? '₹ ${m!.group(1)}' : 'Applicable',
        type: InsightType.warning,
        detail: 'Extra fee added on top of your base charge.',
      ));
    }
    if (lower.contains('overdue') || lower.contains('past due')) {
      warnings.add(BillInsight(
        title: '⚠️ Overdue Balance Detected',
        value: 'Action needed',
        type: InsightType.warning,
        detail: 'Pay immediately to avoid compounding penalties.',
      ));
    }
    // Flag if no due date found
    if (dueDate == null) {
      final dateMatches = _datePat.allMatches(text).map((m) => m.group(0)!).toSet().toList();
      if (dateMatches.isNotEmpty) {
        warnings.add(BillInsight(
          title: 'Dates found in document',
          value: dateMatches.take(3).join(', '),
          type: InsightType.info,
          detail: 'Verify which date is your payment due date.',
        ));
      }
    }

    // 7. Tips
    final tipRules = [...(_tipMap[billType] ?? []), ..._genericTips];
    final tips = tipRules.map((r) => BillInsight(
      title: r.title,
      value: '💡 Tip',
      type: InsightType.tip,
      detail: r.detail,
    )).toList();

    return BillResult(
      billType: billType,
      totalAmount: totalAmount,
      dueDate: dueDate,
      rawText: text,
      charges: charges,
      taxes: taxes,
      warnings: warnings,
      tips: tips,
    );
  }

  static bool _isTaxLabel(String lbl) {
    final l = lbl.toLowerCase();
    return ['gst','vat','cgst','sgst','igst','cess','tax'].any((t) => l.contains(t));
  }

  static String _cleanLabel(String s) =>
      s.replaceAll(RegExp(r'[\:\-\s]+$'), '').replaceAll(RegExp(r'\s+'), ' ').trim();

  static String _taxLabel(String raw) {
    final l = raw.toLowerCase();
    if (l.contains('cgst')) return 'CGST';
    if (l.contains('sgst')) return 'SGST';
    if (l.contains('igst')) return 'IGST';
    if (l.contains('gst')) return 'GST';
    if (l.contains('vat')) return 'VAT';
    if (l.contains('cess')) return 'Cess';
    if (l.contains('service tax')) return 'Service Tax';
    return 'Tax';
  }
}

// ════════════════════════════════════════════════════════════
//  MAIN PAGE
// ════════════════════════════════════════════════════════════

class BillScanPage extends StatefulWidget {
  const BillScanPage({super.key});
  @override
  State<BillScanPage> createState() => _BillScanPageState();
}

class _BillScanPageState extends State<BillScanPage> with TickerProviderStateMixin {
  String? _fileName;
  BillResult? _result;
  bool _isLoading = false;
  String _loadingStep = '';
  String? _error;
  int _activeTab = 0;

  late AnimationController _shimmerCtrl;
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  final _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

  @override
  void initState() {
    super.initState();
    _shimmerCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _shimmerCtrl.dispose();
    _fadeCtrl.dispose();
    _textRecognizer.close();
    super.dispose();
  }

  // ── Core Flow ─────────────────────────────────────────────
  // PDF  →  pdfx renders each page to PNG image
  //      →  ML Kit OCR reads image → text
  //      →  BillParser regex → structured insights

  Future<void> _pickAndScan() async {
    setState(() { _error = null; _result = null; });

    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (picked == null || picked.files.single.path == null) return;

      setState(() {
        _fileName = picked.files.single.name;
        _isLoading = true;
        _loadingStep = 'Opening PDF…';
      });

      final document = await PdfDocument.openFile(picked.files.single.path!);
      final total = document.pagesCount;
      final allText = StringBuffer();

      for (int i = 1; i <= total; i++) {
        setState(() => _loadingStep = 'ML Kit OCR — page $i of $total…');

        final page = await document.getPage(i);
        // Render at 2× for better OCR accuracy
        final img = await page.render(
          width: page.width * 2,
          height: page.height * 2,
          format: PdfPageImageFormat.png,
        );
        await page.close();
        if (img == null) continue;

        // Write to temp file — ML Kit needs a file path
        final tmp = await getTemporaryDirectory();
        final imgFile = File('${tmp.path}/ocr_page_$i.png');
        await imgFile.writeAsBytes(img.bytes);

        final recognized = await _textRecognizer.processImage(
          InputImage.fromFilePath(imgFile.path),
        );
        allText.writeln(recognized.text);
        await imgFile.delete();
      }

      await document.close();

      setState(() => _loadingStep = 'Parsing bill…');
      final text = allText.toString().trim();
      if (text.isEmpty) {
        throw Exception('No text extracted. Ensure the PDF is not a blank image.');
      }

      final result = BillParser.parse(text);
      setState(() { _result = result; _isLoading = false; _activeTab = 0; });
      _fadeCtrl.forward(from: 0);
    } catch (e) {
      setState(() { _isLoading = false; _error = e.toString(); });
    }
  }

  // ── Build ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A14),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Column(children: [
                  const SizedBox(height: 20),
                  _buildUploadButton(),
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
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A14),
        border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.06))),
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
          const Text('BillScan', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
          Text('ML Kit OCR  •  Regex Parser  •  100% Offline', style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 10.5)),
        ]),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFF4ECDC4).withOpacity(0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF4ECDC4).withOpacity(0.3)),
          ),
          child: const Text('FREE', style: TextStyle(color: Color(0xFF4ECDC4), fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1)),
        ),
      ]),
    );
  }

  Widget _buildUploadButton() {
    return GestureDetector(
      onTap: _isLoading ? null : _pickAndScan,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
        decoration: BoxDecoration(
          color: const Color(0xFF13131F),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _result != null
                ? const Color(0xFF4ECDC4).withOpacity(0.4)
                : Colors.white.withOpacity(0.09),
            width: 1.5,
          ),
        ),
        child: Column(children: [
          Icon(
            _result != null ? Icons.check_circle_rounded : Icons.upload_file_rounded,
            color: _result != null ? const Color(0xFF4ECDC4) : Colors.white38,
            size: 38,
          ),
          const SizedBox(height: 10),
          Text(
            _fileName ?? 'Tap to select a PDF bill',
            style: TextStyle(
              color: Colors.white.withOpacity(_fileName != null ? 0.9 : 0.45),
              fontWeight: FontWeight.w600, fontSize: 15,
            ),
            textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            _result != null ? 'Tap to scan a different PDF' : 'Electricity • Phone • Water • Credit Card • Gas',
            style: TextStyle(color: Colors.white.withOpacity(0.28), fontSize: 12),
          ),
        ]),
      ),
    );
  }

  Widget _buildLoader() {
    return AnimatedBuilder(
      animation: _shimmerCtrl,
      builder: (_, __) => Column(children: [
        SizedBox(
          width: 48, height: 48,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            color: Color.lerp(const Color(0xFF4ECDC4), const Color(0xFF2BAE9F), _shimmerCtrl.value),
          ),
        ),
        const SizedBox(height: 14),
        Text(_loadingStep, style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14, fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        Text('No internet required', style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 12)),
      ]),
    );
  }

  Widget _buildErrorCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFF6B6B).withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFF6B6B).withOpacity(0.3)),
      ),
      child: Row(children: [
        const Icon(Icons.error_outline_rounded, color: Color(0xFFFF6B6B)),
        const SizedBox(width: 10),
        Expanded(child: Text(_error!, style: const TextStyle(color: Color(0xFFFFAAAA), fontSize: 13))),
      ]),
    );
  }

  // ── Results ───────────────────────────────────────────────

  Widget _buildResults() {
    final r = _result!;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _buildSummaryBanner(r),
      const SizedBox(height: 20),
      _buildTabBar(r),
      const SizedBox(height: 16),
      _buildTabContent(r),
    ]);
  }

  Widget _buildSummaryBanner(BillResult r) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFF142020), Color(0xFF111E1E)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF4ECDC4).withOpacity(0.25)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF4ECDC4).withOpacity(0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(r.billType.toUpperCase(),
                style: const TextStyle(color: Color(0xFF4ECDC4), fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
          ),
          const SizedBox(height: 10),
          Text('Total Amount', style: TextStyle(color: Colors.white.withOpacity(0.38), fontSize: 12)),
          Text(
            r.totalAmount ?? 'Not detected',
            style: TextStyle(
              color: r.totalAmount != null ? Colors.white : Colors.white30,
              fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.8,
            ),
          ),
        ])),
        if (r.dueDate != null)
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('Due Date', style: TextStyle(color: Colors.white.withOpacity(0.38), fontSize: 11)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFFFF6B6B).withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFF6B6B).withOpacity(0.3)),
              ),
              child: Text(r.dueDate!,
                  style: const TextStyle(color: Color(0xFFFF9999), fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ]),
      ]),
    );
  }

  static const _tabLabels = ['Charges', 'Taxes', 'Warnings', 'Tips'];
  static const _tabIcons = [
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
        final col = _tabColors[i];
        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _activeTab = i),
            child: Container(
              margin: EdgeInsets.only(right: i < _tabLabels.length - 1 ? 8 : 0),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: active ? col.withOpacity(0.12) : const Color(0xFF13131F),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: active ? col.withOpacity(0.45) : Colors.white.withOpacity(0.07),
                ),
              ),
              child: Column(children: [
                Icon(_tabIcons[i], color: active ? col : Colors.white24, size: 16),
                const SizedBox(height: 3),
                Text(_tabLabels[i],
                    style: TextStyle(color: active ? col : Colors.white24, fontSize: 9.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text('${counts[i]}',
                    style: TextStyle(color: active ? col.withOpacity(0.7) : Colors.white12, fontSize: 9, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildTabContent(BillResult r) {
    final List<BillInsight> items;
    final Color col;
    final String empty;
    switch (_activeTab) {
      case 0: items = r.charges; col = _tabColors[0]; empty = 'No itemised charges found.\nCheck the raw text if the PDF is image-heavy.'; break;
      case 1: items = r.taxes; col = _tabColors[1]; empty = 'No tax lines detected.'; break;
      case 2: items = r.warnings; col = _tabColors[2]; empty = '✅  No warnings — this bill looks clean!'; break;
      case 3: items = r.tips; col = _tabColors[3]; empty = 'No tips available.'; break;
      default: return const SizedBox();
    }
    if (items.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(color: const Color(0xFF13131F), borderRadius: BorderRadius.circular(16)),
        child: Center(child: Text(empty, textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withOpacity(0.38), fontSize: 13, height: 1.5))),
      );
    }
    return Column(children: items.map((item) => _buildTile(item, col)).toList());
  }

  Widget _buildTile(BillInsight insight, Color color) {
    final icon = switch (insight.type) {
      InsightType.charge => Icons.receipt_rounded,
      InsightType.tax => Icons.account_balance_rounded,
      InsightType.warning => Icons.warning_amber_rounded,
      InsightType.tip => Icons.lightbulb_rounded,
      InsightType.date => Icons.calendar_today_rounded,
      InsightType.info => Icons.info_rounded,
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.14)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(color: color.withOpacity(0.14), borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: color, size: 14),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(insight.title,
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600))),
            Text(insight.value, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
          ]),
          if (insight.detail != null) ...[
            const SizedBox(height: 4),
            Text(insight.detail!, style: TextStyle(color: Colors.white.withOpacity(0.38), fontSize: 12, height: 1.4)),
          ],
        ])),
      ]),
    );
  }
}