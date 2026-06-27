import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:goride/pages/chat_conversation_list_screen.dart';

class DeepLinkService extends GetxService {
  final _appLinks = AppLinks();

  @override
  void onInit() {
    super.onInit();
    _handleInitialLink();
    _listenForLinks();
  }

  Future<void> _handleInitialLink() async {
    try {
      final uri = await _appLinks.getInitialLink();
      if (uri != null) _route(uri);
    } catch (e) {
      debugPrint('Deep link initial error: $e');
    }
  }

  void _listenForLinks() {
    _appLinks.uriLinkStream.listen(
      (uri) => _route(uri),
      onError: (e) => debugPrint('Deep link stream error: $e'),
    );
  }

  void _route(Uri uri) {
    debugPrint('Deep link received: $uri');
    // goride://chat  →  open conversation list
    if (uri.host == 'chat') {
      Get.to(() => const ChatConversationListScreen());
      return;
    }
    // goride://track/TRIP_ID  →  could open live tracking (extend as needed)
    if (uri.host == 'track') {
      // tripId is uri.pathSegments.first if present
      // For now just navigate home; extend when trip tracking page is ready
      Get.offAllNamed('/home');
      return;
    }
  }
}
