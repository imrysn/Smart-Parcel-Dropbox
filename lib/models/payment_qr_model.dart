class PaymentQrModel {
  final String userId;
  final String? gcashName;
  final String? gcashNumber;
  final String? mayaName;
  final String? mayaNumber;
  final String? bankName;
  final String? bankAccountName;
  final String? bankAccountNumber;
  final String? qrPhImageUrl;

  PaymentQrModel({
    required this.userId,
    this.gcashName,
    this.gcashNumber,
    this.mayaName,
    this.mayaNumber,
    this.bankName = 'BDO / BPI / UnionBank',
    this.bankAccountName,
    this.bankAccountNumber,
    this.qrPhImageUrl,
  });

  factory PaymentQrModel.fromMap(Map<String, dynamic> data) {
    return PaymentQrModel(
      userId: data['userId']?.toString() ?? '',
      gcashName: data['gcashName']?.toString(),
      gcashNumber: data['gcashNumber']?.toString(),
      mayaName: data['mayaName']?.toString(),
      mayaNumber: data['mayaNumber']?.toString(),
      bankName: data['bankName']?.toString() ?? 'BDO / BPI / UnionBank',
      bankAccountName: data['bankAccountName']?.toString(),
      bankAccountNumber: data['bankAccountNumber']?.toString(),
      qrPhImageUrl: data['qrPhImageUrl']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'gcashName': gcashName,
      'gcashNumber': gcashNumber,
      'mayaName': mayaName,
      'mayaNumber': mayaNumber,
      'bankName': bankName,
      'bankAccountName': bankAccountName,
      'bankAccountNumber': bankAccountNumber,
      'qrPhImageUrl': qrPhImageUrl,
    };
  }
}
