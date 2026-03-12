🧾 BillScan – OCR-Based Bill Analysis App

BillScan is a mobile application that uses Google ML Kit OCR and intelligent text parsing to extract meaningful information from bills and invoices.

The app analyzes PDF bills to identify charges, taxes, warnings, and financial insights, helping users better understand their expenses and avoid hidden costs.

BillScan works completely offline, ensuring fast processing and user privacy.

<img width="235" height="522" alt="image" src="https://github.com/user-attachments/assets/d37fa281-7196-4e0b-8251-12378396efff" />
<img width="232" height="521" alt="image" src="https://github.com/user-attachments/assets/016beba4-990d-4c80-ba5d-52abf7a21ec9" />
<img width="231" height="520" alt="image" src="https://github.com/user-attachments/assets/36be12e0-e9b5-483e-9aec-778f2d134cb0" />


other examples:
<img width="235" height="523" alt="image" src="https://github.com/user-attachments/assets/d5fcf270-ca38-4463-ab99-324241d88b31" />
<img width="250" height="523" alt="image" src="https://github.com/user-attachments/assets/0c4690ae-f3b2-49ad-8a5a-9e63e3ec3e47" />



 🚀 Features

 📄 PDF Bill Scanning

- Upload and analyze PDF bills
- Extract raw text using Google ML Kit OCR
- Supports invoices, grocery bills, and service bills

 🔍 Intelligent Text Parsing

- Uses regex-based parsing to detect:

  - Itemized charges
  - Prices
  - Product descriptions
  - Invoice data

 💰 Charge Detection

Automatically identifies individual bill items such as:

- Product names
- Unit prices
- Itemized charges
- Total cost

 🧾 Tax Identification

Detects tax-related entries like:

- GST
- IGST
- Service tax
- Other bill charges

Displays tax details clearly in the Taxes section.

 ⚠️ Smart Warning System

BillScan detects potentially important information such as:

- Dates found in the document
- Possible due dates
- Irregular entries

Example warning:

```
Dates found in document: 16/5/1978
Verify which date is your payment due date.
```

 💡 Financial Tips Generator

Based on detected bill data, the app provides helpful tips such as:

- Go paperless to avoid extra charges
- Pay bills before due dates
- Review service plans annually

These insights help users make smarter financial decisions.

 🔐 100% Offline Processing

BillScan performs all analysis directly on the device:

- No cloud uploads
- No external API calls
- Faster and privacy-friendly processing

---

 🛠️ Tech Stack

 Mobile Framework

- Flutter

 OCR Engine

- Google ML Kit Text Recognition

 Data Processing

- Regex-based parsing
- Text filtering
- Pattern detection

 UI

- Custom Flutter UI
- Dark fintech-style interface

---

 📱 App Workflow

```
Upload PDF
     ↓
ML Kit OCR extracts raw text
     ↓
Regex parser identifies:
     - charges
     - taxes
     - warnings
     ↓
BillScan generates:
     - bill summary
     - warnings
     - financial tips
```

---

 📷 Screenshots

Example features demonstrated in the app:

- Bill upload and OCR detection
- Automatic charge extraction
- Tax analysis
- Warning detection
- Smart financial tips

-(Add your screenshots here)-

---

 💡 Example Output

Total Amount

```
₹ 91.00
```

Detected Charges

```
Island Oasis Strawberry - $72
Cumin Ground - $19
```

Warnings

```
Dates found in document
Verify which date is your payment due date
```

Tips

```
Go paperless
Pay 2–3 days before due date
Review plans annually
```

---

 📈 Future Improvements

Possible enhancements for the project:

- Camera-based bill scanning
- AI-based expense categorization
- Spending analytics dashboard
- Fraud or hidden charge detection
- Multi-language OCR support

---

 👨‍💻 Author

Sahil Patil

Computer Engineering Student
Interested in AI-powered applications, full-stack development, and intelligent automation.

---

⭐ If you like this project, consider starring the repository!
