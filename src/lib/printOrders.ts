// Shared print helpers for stickers and invoices
export function printStickers(orders: any[]) {
  if (!orders.length) return;
  const w = window.open('', '_blank', 'width=400,height=600');
  if (!w) return;
  const stickers = orders.map(order => {
    const total = Number(order.price) + Number(order.delivery_price);
    const barcode = order.barcode || '';
    return `
      <div class="sticker">
        <div class="header">TikExpress</div>
        <div class="date">${new Date(order.created_at).toLocaleDateString('ar-EG')}</div>
        <div class="barcode-num">${barcode}</div>
        <div class="row"><span>الكود: <b>${order.customer_code || '-'}</b></span></div>
        <div class="info">العميل: <b>${order.customer_name}</b></div>
        <div class="info">المكتب: <b>${order.offices?.name || '-'}</b></div>
        <div class="info">هاتف: <b dir="ltr">${order.customer_phone}</b></div>
        <div class="info">العنوان: <b>${order.address || '-'}</b></div>
        <div class="info">قطع: <b>${order.quantity || 1}</b> ${order.size ? `| مقاس: <b>${order.size}</b>` : ''} ${order.color ? `| لون: <b>${order.color}</b>` : ''}</div>
        <div class="total">${total} ج.م</div>
      </div>`;
  }).join('');
  w.document.write(`<!DOCTYPE html><html dir="rtl"><head><meta charset="UTF-8">
    <style>
      @page { size: 50mm 100mm; margin: 0; }
      body { font-family: 'Segoe UI', Arial, sans-serif; margin: 0; padding: 0; }
      .sticker { width: 50mm; height: 100mm; padding: 4mm 1.5mm 4mm 10mm; box-sizing: border-box; page-break-after: always; display: flex; flex-direction: column; direction: rtl; text-align: right; }
      .sticker:last-child { page-break-after: auto; }
      .header { text-align: center; font-size: 16px; font-weight: bold; margin-bottom: 1px; direction: ltr; }
      .date { text-align: center; font-size: 8px; margin-bottom: 3px; color: #333; }
      .barcode-num { font-family: monospace; font-size: 17px; font-weight: bold; margin-bottom: 4px; text-align: center; }
      .info { margin: 2px 0; font-size: 10px; line-height: 1.4; text-align: right; word-wrap: break-word; }
      .row { display: flex; justify-content: space-between; margin: 2px 0; font-size: 10px; }
      .total { font-size: 15px; font-weight: bold; text-align: center; border: 1.5px solid #000; padding: 3px; margin-top: auto; }
    </style></head><body>${stickers}</body></html>`);
  w.document.close(); w.focus(); w.print();
}

export function printInvoices(orders: any[]) {
  if (!orders.length) return;
  const w = window.open('', '_blank', 'width=800,height=1000');
  if (!w) return;
  const invoicesHtml = orders.map((order, i) => {
    const total = Number(order.price) + Number(order.delivery_price);
    return `
      <div class="invoice-page">
        <div class="header">TikExpress</div>
        <div class="date">${new Date().toLocaleDateString('ar-EG')} - فاتورة ${i + 1} من ${orders.length}</div>
        <table>
          <tr><th>الكود</th><td>${order.customer_code || '-'}</td></tr>
          <tr><th>الباركود</th><td style="font-family:monospace;direction:ltr">${order.barcode || ''}</td></tr>
          <tr><th>اسم العميل</th><td>${order.customer_name}</td></tr>
          <tr><th>الهاتف</th><td dir="ltr">${order.customer_phone}</td></tr>
          <tr><th>المكتب</th><td>${order.offices?.name || '-'}</td></tr>
          <tr><th>العنوان</th><td>${order.address || '-'}</td></tr>
          <tr><th>المنتج</th><td>${order.product_name || '-'}</td></tr>
          <tr><th>الكمية</th><td>${order.quantity}</td></tr>
          <tr><th>السعر</th><td>${Number(order.price)} ج.م</td></tr>
          <tr><th>الشحن</th><td>${Number(order.delivery_price)} ج.م</td></tr>
        </table>
        <div class="total">الإجمالي: ${total} ج.م</div>
      </div>`;
  }).join('');
  w.document.write(`<!DOCTYPE html><html dir="rtl"><head><meta charset="UTF-8">
    <style>
      @page { size: A4; margin: 15mm; }
      body { font-family: 'Segoe UI', Arial, sans-serif; margin: 0; padding: 0; }
      .invoice-page { page-break-after: always; padding: 10mm 0; }
      .invoice-page:last-child { page-break-after: auto; }
      .header { text-align: center; font-size: 28px; font-weight: bold; margin-bottom: 10px; }
      .date { text-align: center; margin-bottom: 20px; color: #666; font-size: 13px; }
      table { width: 100%; border-collapse: collapse; margin-bottom: 20px; }
      th, td { border: 1px solid #333; padding: 10px 14px; text-align: right; font-size: 14px; }
      th { background: #f0f0f0; font-weight: bold; width: 30%; }
      .total { font-size: 22px; font-weight: bold; text-align: center; border: 3px solid #000; padding: 12px; }
    </style></head><body>${invoicesHtml}</body></html>`);
  w.document.close(); w.focus(); w.print();
}
