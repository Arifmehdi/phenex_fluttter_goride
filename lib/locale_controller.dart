import 'package:get/get.dart';

class LocaleController extends GetxController {
  var isEnglish = true.obs;

  void toggleLocale() {
    isEnglish.value = !isEnglish.value;
  }

  String get(String en, String bn) {
    return isEnglish.value ? en : bn;
  }
}
