import 'package:dio/dio.dart';
import 'package:get/get.dart' as g;
import 'api_service.dart';

class SslCommerzService extends g.GetxController {
  final String storeId = '93sha6a1ff5f06a9b9';
  final String storePass = '93sha6a1ff5f06a9b9@ssl';
  final String initUrl = 'https://sandbox.sslcommerz.com/gwprocess/v4/api.php';
  
  final Dio _dio = Dio();

  Future<String?> initiatePayment({
    required double amount,
    required String transactionId,
    required String customerName,
    required String customerEmail,
    required String customerPhone,
  }) async {
    try {
      final formData = FormData.fromMap({
        'store_id': storeId,
        'store_passwd': storePass,
        'total_amount': amount.toStringAsFixed(2),
        'currency': 'BDT',
        'tran_id': transactionId,
        'success_url': 'https://goride.app/payment-success',
        'fail_url': 'https://goride.app/payment-fail',
        'cancel_url': 'https://goride.app/payment-cancel',
        'cus_name': customerName,
        'cus_email': customerEmail,
        'cus_add1': 'Dhaka',
        'cus_city': 'Dhaka',
        'cus_postcode': '1212',
        'cus_country': 'Bangladesh',
        'cus_phone': customerPhone,
        'shipping_method': 'NO',
        'product_name': 'Ride Booking',
        'product_category': 'Service',
        'product_profile': 'non-physical-goods',
      });

      final response = await _dio.post(initUrl, data: formData);

      if (response.statusCode == 200) {
        final data = response.data;
        if (data['status'] == 'SUCCESS') {
          return data['GatewayPageURL'];
        } else {
          print('SSLCommerz Error: ${data['failedreason']}');
        }
      }
    } catch (e) {
      print('SSLCommerz Initiation Failed: $e');
    }
    return null;
  }
}
