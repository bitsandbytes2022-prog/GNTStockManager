// Converts a rupee amount into the "INR ... Only" wording used on printed
// tax invoices, using the Indian numbering system (thousand/lakh/crore).
String amountInWords(double amount) {
  final rupees = amount.floor();
  final paise = ((amount - rupees) * 100).round();

  final rupeesWords = _numberToWordsIndian(rupees);
  if (paise > 0) {
    return 'INR $rupeesWords and ${_numberToWordsIndian(paise)} Paise Only';
  }
  return 'INR $rupeesWords Only';
}

const _ones = [
  '', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine',
  'Ten', 'Eleven', 'Twelve', 'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen',
  'Seventeen', 'Eighteen', 'Nineteen',
];
const _tens = [
  '', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety',
];

String _twoDigits(int n) {
  if (n < 20) return _ones[n];
  final ten = _tens[n ~/ 10];
  final one = n % 10;
  return one == 0 ? ten : '$ten ${_ones[one]}';
}

String _threeDigits(int n) {
  final hundred = n ~/ 100;
  final rest = n % 100;
  final parts = <String>[];
  if (hundred > 0) parts.add('${_ones[hundred]} Hundred');
  if (rest > 0) parts.add(_twoDigits(rest));
  return parts.join(' ');
}

String _numberToWordsIndian(int number) {
  if (number == 0) return 'Zero';

  final crore = number ~/ 10000000;
  number %= 10000000;
  final lakh = number ~/ 100000;
  number %= 100000;
  final thousand = number ~/ 1000;
  number %= 1000;
  final hundred = number;

  final parts = <String>[];
  if (crore > 0) parts.add('${_threeDigits(crore)} Crore');
  if (lakh > 0) parts.add('${_threeDigits(lakh)} Lakh');
  if (thousand > 0) parts.add('${_threeDigits(thousand)} Thousand');
  if (hundred > 0) parts.add(_threeDigits(hundred));

  return parts.join(' ');
}
