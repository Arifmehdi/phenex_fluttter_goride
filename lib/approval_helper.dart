import 'package:flutter/foundation.dart';

/// Checks if a user registration/login response indicates the account is
/// pending admin approval.
///
/// Checks multiple indicators:
/// 1. Direct `pending` flag from registration response
/// 2. Direct `is_approved` flag from login response (false = pending)
/// 3. User's `status` field (0 or 'pending' = pending)
bool isPendingApproval(dynamic responseData) {
  if (responseData == null) return false;

  // Debug logging
  debugPrint('Approval check - response data: $responseData');

  // Check 1: Direct 'pending' flag from registration response
  if (responseData['pending'] == true) {
    debugPrint('Approval check: pending flag is TRUE');
    return true;
  }

  // Check 2: Direct 'is_approved' flag from login response
  if (responseData['is_approved'] == false) {
    debugPrint('Approval check: is_approved is FALSE');
    return true;
  }

  // Check 3: User's 'status' field from the user object
  final userData = responseData['user'];
  if (userData != null && userData is Map) {
    final status = userData['status'];
    debugPrint('Approval check - user status: $status (${status.runtimeType})');
    if (status == 0 || status == '0' || status == 'pending') {
      debugPrint('Approval check: user status indicates pending ($status)');
      return true;
    }
  }

  debugPrint('Approval check: not pending (approved)');
  return false;
}
