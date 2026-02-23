export class PushGateway {
  async sendPendingApproval(notification) {
    // Integrate FCM/APNs here. This no-op is intentionally safe for local dev.
    // eslint-disable-next-line no-console
    console.log('[Sentinel] Push queued for Toney device', {
      appointmentId: notification.appointmentId,
      action: notification.action,
      startTime: notification.startTime?.toISOString?.() ?? notification.startTime,
    });
  }
}

export const pushGateway = new PushGateway();
