export class WebhookClient {
  async postConfirmation({ url, payload, headers = {} }) {
    if (!url) return;

    const response = await fetch(url, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        ...headers,
      },
      body: JSON.stringify(payload),
    });

    if (!response.ok) {
      const body = await response.text().catch(() => '');
      throw new Error(`Webhook failed (${response.status}): ${body.slice(0, 200)}`);
    }
  }
}

export const webhookClient = new WebhookClient();
