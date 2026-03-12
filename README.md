🧾 BillScan – OCR-Based Bill Analysis App

BillScan is a mobile application that uses Google ML Kit OCR and intelligent text parsing to extract meaningful information from bills and invoices.

The app analyzes PDF bills to identify charges, taxes, warnings, and financial insights, helping users better understand their expenses and avoid hidden costs.

BillScan works completely offline, ensuring fast processing and user privacy.


![WhatsApp Image 2026-03-04 at 23 54 58](https://github.com/user-attachments/assets/08cf2411-6960-41a9-b34f-3c29004bee3a)
![WhatsApp Image 2026-03-05 at 00 32 02](https://github.com/user-attachments/assets/fb35d33c-7b75-4b45-a99b-a1747ab69bf5)
![WhatsApp Image 2026-03-05 at 00 31 32](https://github.com/user-attachments/assets/c10f3b6f-35ec-4f8e-97da-ff6ce3cee65f)
![WhatsApp Image 2026-03-05 at 00 31 10](https://github.com/user-attachments/assets/834b1519-e45b-4dfe-b8f1-9f06fcee24bc)
![WhatsApp Image 2026-03-04 at 23 55 54](https://github.com/user-attachments/assets/0a4c8edc-1e13-4f17-aeda-d8f5eeb3d86a)
![WhatsApp Image 2026-03-04 at 23 55 32](https://github.com/user-attachments/assets/9cdec5a1-7f2d-44b2-b0ea-fd055e1cec28)



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
