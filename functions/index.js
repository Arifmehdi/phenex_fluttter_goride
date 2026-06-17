/**
 * GoRide Ride Request Timeout Handler
 * 
 * When a ride request is created:
 * 1. Wait 10 seconds
 * 2. If the request is still 'pending', mark it as 'cancelled' with reason 'timeout'
 * 3. The Flutter app listens for this status change to hide the request
 * 
 * This ensures that if no driver accepts within 10 seconds,
 * the request is automatically cleared and can be re-offered.
 */

const functions = require('firebase-functions');
const admin = require('firebase-admin');

admin.initializeApp();

const db = admin.firestore();

/**
 * Firestore trigger: on ride_requests document creation
 * Waits 10 seconds, then cancels if still pending
 */
exports.handleRideRequestTimeout = functions.firestore
  .document('ride_requests/{requestId}')
  .onCreate(async (snap, context) => {
    const requestId = context.params.requestId;
    const data = snap.data();
    
    // Only process pending requests
    if (data.status !== 'pending') {
      console.log(`Request ${requestId} status is "${data.status}", not pending. Skipping.`);
      return;
    }

    console.log(`Ride request ${requestId} created. Starting 10s timeout for driver matching...`);

    // Wait 10 seconds
    await new Promise(resolve => setTimeout(resolve, 10000));

    try {
      // Re-fetch the document to get the latest status
      const docSnap = await db.collection('ride_requests').doc(requestId).get();
      
      if (!docSnap.exists) {
        console.log(`Request ${requestId} no longer exists. Skipping.`);
        return;
      }

      const currentData = docSnap.data();
      
      // Only cancel if still pending (not yet accepted by any driver)
      if (currentData.status === 'pending') {
        await db.collection('ride_requests').doc(requestId).update({
          status: 'cancelled',
          cancelReason: 'timeout',
          cancelledAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        
        console.log(`Ride request ${requestId} auto-cancelled after 10s timeout.`);
      } else {
        console.log(`Ride request ${requestId} was ${currentData.status}. No action needed.`);
      }
    } catch (error) {
      console.error(`Error handling timeout for request ${requestId}:`, error);
    }
  });

// Note: Active trip updates are handled by the Flutter client via FirebaseService.assignDriverToTrip().
// No server-side duplicate update needed to avoid race conditions.
