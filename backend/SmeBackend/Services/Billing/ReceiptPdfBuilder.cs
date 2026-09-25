using System.Globalization;
using System.Text;
using System.Text.Json;
using SmeBackend.DTOs;

namespace SmeBackend.Services.Billing;

/// Renders a receipt/invoice as a PDF, laid out by the tenant's invoice
/// template (block order + visibility from the Invoice Designer).
///
/// A small hand-written PDF 1.4 writer rather than a library: the output is
/// text, rules and filled rectangles in the two standard Helvetica faces,
/// which every PDF viewer ships, so no font embedding and no dependency.
public static class ReceiptPdfBuilder
{
    public static readonly string[] DefaultBlocks =
        { "header", "invoiceMeta", "customerInfo", "items", "totals", "payments", "notes", "footer" };

    private const float PageWidth = 595f;   // A4
    private const float PageHeight = 842f;
    private const float Margin = 48f;
    private const float Bottom = 56f;

    public static byte[] Build(ReceiptResponse r, bool asReceipt = true)
    {
        var accent = ParseColor(r.Template?.AccentColor) ?? (0.145f, 0.388f, 0.922f);
        var doc = new Document(accent);
        var blocks = ResolveBlocks(r.Template?.Layout);

        foreach (var block in blocks)
        {
            switch (block)
            {
                case "header": Header(doc, r, asReceipt); break;
                case "businessInfo": BusinessInfo(doc, r); break;
                case "invoiceMeta": Meta(doc, r); break;
                case "customerInfo": Customer(doc, r); break;
                case "items": Items(doc, r); break;
                case "totals": Totals(doc, r); break;
                case "payments": Payments(doc, r); break;
                case "notes": Notes(doc, r); break;
                case "footer": Footer(doc, r); break;
            }
        }

        return doc.Render();
    }

    /// The template's visible blocks in its order; unknown ids are ignored,
    /// and a missing or empty layout falls back to the default order.
    public static IReadOnlyList<string> ResolveBlocks(JsonElement? layout)
    {
        if (layout is not { ValueKind: JsonValueKind.Array } arr) return DefaultBlocks;
        var result = new List<string>();
        foreach (var item in arr.EnumerateArray())
        {
            if (item.ValueKind != JsonValueKind.Object) continue;
            var type = item.TryGetProperty("type", out var t) && t.ValueKind == JsonValueKind.String ? t.GetString() : null;
            var visible = !item.TryGetProperty("visible", out var v) || v.ValueKind != JsonValueKind.False;
            if (type is not null && visible && !result.Contains(type)) result.Add(type);
        }
        return result.Count == 0 ? DefaultBlocks : result;
    }

    // ------------------------------------------------------------------
    private static void Header(Document d, ReceiptResponse r, bool asReceipt)
    {
        d.Ensure(96);
        d.FillRect(0, d.Y - 70, PageWidth, 90, d.Accent);
        d.Text(Margin, d.Y - 22, 20, bold: true, r.BusinessName ?? "Invoice", white: true);
        if (!string.IsNullOrWhiteSpace(r.Template?.HeaderText))
            d.Text(Margin, d.Y - 42, 9, bold: false, r.Template!.HeaderText!, white: true);
        d.TextRight(PageWidth - Margin, d.Y - 22, 16, bold: true, asReceipt ? "RECEIPT" : "INVOICE", white: true);
        d.TextRight(PageWidth - Margin, d.Y - 42, 10, bold: false, asReceipt ? r.ReceiptNumber : r.InvoiceNumber, white: true);
        d.Y -= 100;
    }

    private static void BusinessInfo(Document d, ReceiptResponse r)
    {
        if (string.IsNullOrWhiteSpace(r.BusinessName)) return;
        d.Ensure(24);
        d.Text(Margin, d.Y, 11, bold: true, r.BusinessName!);
        d.Y -= 22;
    }

    private static void Meta(Document d, ReceiptResponse r)
    {
        d.Ensure(64);
        var rows = new (string, string)[]
        {
            ("Invoice", r.InvoiceNumber),
            ("Issued", r.IssuedAt.ToString("dd MMM yyyy", CultureInfo.InvariantCulture)),
            ("Due", r.DueDate.ToString("dd MMM yyyy", CultureInfo.InvariantCulture)),
            ("Status", r.PaymentStatus),
        };
        var x = Margin;
        foreach (var (label, value) in rows)
        {
            d.Text(x, d.Y, 8, bold: false, label.ToUpperInvariant(), muted: true);
            d.Text(x, d.Y - 14, 10, bold: true, value);
            x += 125;
        }
        d.Y -= 40;
    }

    private static void Customer(Document d, ReceiptResponse r)
    {
        d.Ensure(50);
        d.Text(Margin, d.Y, 8, bold: false, "BILLED TO", muted: true);
        d.Text(Margin, d.Y - 14, 11, bold: true, r.CustomerName ?? r.CustomerId.ToString());
        if (!string.IsNullOrWhiteSpace(r.CustomerEmail))
            d.Text(Margin, d.Y - 28, 9, bold: false, r.CustomerEmail!);
        d.Y -= 46;
    }

    private static void Items(Document d, ReceiptResponse r)
    {
        const float qtyX = 340, priceX = 440, amountX = PageWidth - Margin;
        void HeaderRow()
        {
            d.FillRect(Margin - 6, d.Y - 6, PageWidth - 2 * Margin + 12, 20, (0.95f, 0.95f, 0.96f));
            d.Text(Margin, d.Y, 8, bold: true, "DESCRIPTION");
            d.TextRight(qtyX, d.Y, 8, bold: true, "QTY");
            d.TextRight(priceX, d.Y, 8, bold: true, "UNIT PRICE");
            d.TextRight(amountX, d.Y, 8, bold: true, $"AMOUNT ({r.Currency})");
            d.Y -= 22;
        }

        d.Ensure(60);
        HeaderRow();
        foreach (var item in r.Items)
        {
            if (d.Ensure(20)) HeaderRow();
            d.Text(Margin, d.Y, 10, bold: false, Truncate(item.Description, 48));
            if (!string.IsNullOrWhiteSpace(item.Category) && item.Category != "General")
                d.Text(Margin, d.Y - 11, 7, bold: false, item.Category, muted: true);
            d.TextRight(qtyX, d.Y, 10, bold: false, item.Quantity.ToString(CultureInfo.InvariantCulture));
            d.TextRight(priceX, d.Y, 10, bold: false, Money(item.UnitPrice));
            d.TextRight(amountX, d.Y, 10, bold: false, Money(item.Amount));
            d.Y -= string.IsNullOrWhiteSpace(item.Category) || item.Category == "General" ? 18 : 24;
            d.Line(Margin, d.Y + 8, PageWidth - Margin, d.Y + 8);
        }
        d.Y -= 8;
    }

    private static void Totals(Document d, ReceiptResponse r)
    {
        var rows = new List<(string Label, string Value, bool Bold)>
        {
            ("Subtotal", Money(r.TotalAmount), false),
        };
        if (r.Discount > 0) rows.Add(("Discount", "-" + Money(r.Discount), false));
        if (r.Tax > 0) rows.Add(("Tax", Money(r.Tax), false));
        rows.Add(($"Total ({r.Currency})", Money(r.FinalAmount), true));
        rows.Add(("Paid", Money(r.TotalPaid), false));
        rows.Add(("Balance due", Money(r.BalanceDue), true));

        d.Ensure(rows.Count * 18 + 10);
        const float labelX = 380;
        foreach (var (label, value, bold) in rows)
        {
            if (bold) d.FillRect(labelX - 8, d.Y - 5, PageWidth - Margin - labelX + 14, 18, (0.95f, 0.95f, 0.96f));
            d.Text(labelX, d.Y, 10, bold, label);
            d.TextRight(PageWidth - Margin, d.Y, 10, bold, value);
            d.Y -= 18;
        }
        d.Y -= 12;
    }

    private static void Payments(Document d, ReceiptResponse r)
    {
        if (r.Payments.Count == 0) return;
        d.Ensure(40);
        d.Text(Margin, d.Y, 8, bold: true, "PAYMENTS", muted: true);
        d.Y -= 16;
        foreach (var p in r.Payments)
        {
            d.Ensure(16);
            var when = (p.PaidAt ?? p.CreatedAt).ToString("dd MMM yyyy HH:mm", CultureInfo.InvariantCulture);
            var label = $"{when}  -  {p.Method}{(p.PayerLabel is null ? "" : $" ({p.PayerLabel})")}{(p.Status == "Succeeded" ? "" : $"  [{p.Status}]")}";
            d.Text(Margin, d.Y, 9, bold: false, label);
            if (!string.IsNullOrWhiteSpace(p.TransactionRef))
                d.Text(330, d.Y, 8, bold: false, Truncate(p.TransactionRef!, 28), muted: true);
            d.TextRight(PageWidth - Margin, d.Y, 9, bold: false, Money(p.Amount));
            d.Y -= 15;
        }
        d.Y -= 10;
    }

    private static void Notes(Document d, ReceiptResponse r)
    {
        if (string.IsNullOrWhiteSpace(r.Notes)) return;
        d.Ensure(40);
        d.Text(Margin, d.Y, 8, bold: true, "NOTES", muted: true);
        d.Y -= 14;
        foreach (var line in Wrap(r.Notes!, 95))
        {
            d.Ensure(14);
            d.Text(Margin, d.Y, 9, bold: false, line);
            d.Y -= 13;
        }
        d.Y -= 8;
    }

    private static void Footer(Document d, ReceiptResponse r)
    {
        var text = r.Template?.FooterText;
        if (string.IsNullOrWhiteSpace(text)) text = "Thank you for your business.";
        d.Ensure(40);
        d.Line(Margin, d.Y + 6, PageWidth - Margin, d.Y + 6);
        foreach (var line in Wrap(text!, 100))
        {
            d.Text(Margin, d.Y - 8, 8, bold: false, line, muted: true);
            d.Y -= 12;
        }
    }

    // ------------------------------------------------------------------
    private static string Money(decimal v) => v.ToString("N2", CultureInfo.InvariantCulture);

    private static string Truncate(string s, int max) => s.Length <= max ? s : s[..(max - 1)] + "…";

    private static IEnumerable<string> Wrap(string text, int width)
    {
        foreach (var paragraph in text.Replace("\r", "").Split('\n'))
        {
            var line = new StringBuilder();
            foreach (var word in paragraph.Split(' ', StringSplitOptions.RemoveEmptyEntries))
            {
                if (line.Length + word.Length + 1 > width && line.Length > 0)
                {
                    yield return line.ToString();
                    line.Clear();
                }
                if (line.Length > 0) line.Append(' ');
                line.Append(word);
            }
            yield return line.ToString();
        }
    }

    public static (float R, float G, float B)? ParseColor(string? hex)
    {
        if (string.IsNullOrWhiteSpace(hex)) return null;
        var h = hex.Trim().TrimStart('#');
        if (h.Length == 3) h = string.Concat(h.Select(c => $"{c}{c}"));
        if (h.Length != 6 || !int.TryParse(h, NumberStyles.HexNumber, CultureInfo.InvariantCulture, out var rgb)) return null;
        return (((rgb >> 16) & 0xFF) / 255f, ((rgb >> 8) & 0xFF) / 255f, (rgb & 0xFF) / 255f);
    }

    /// Page state + the raw PDF object writer.
    private sealed class Document
    {
        private readonly List<StringBuilder> _pages = new();
        private StringBuilder _page = null!;
        public float Y;
        public (float R, float G, float B) Accent { get; }

        public Document((float, float, float) accent)
        {
            Accent = accent;
            NewPage();
        }

        private void NewPage()
        {
            _page = new StringBuilder();
            _pages.Add(_page);
            Y = PageHeight - 20;
        }

        /// Starts a new page when fewer than `height` points remain; returns
        /// true when it did, so a table can repeat its header row.
        public bool Ensure(float height)
        {
            if (Y - height >= Bottom) return false;
            NewPage();
            Y = PageHeight - Margin;
            return true;
        }

        public void FillRect(float x, float y, float w, float h, (float R, float G, float B) c) =>
            _page.Append(F(c.R)).Append(' ').Append(F(c.G)).Append(' ').Append(F(c.B)).Append(" rg ")
                 .Append(F(x)).Append(' ').Append(F(y)).Append(' ').Append(F(w)).Append(' ').Append(F(h)).Append(" re f\n");

        public void Line(float x1, float y1, float x2, float y2) =>
            _page.Append("0.85 G 0.5 w ").Append(F(x1)).Append(' ').Append(F(y1)).Append(" m ")
                 .Append(F(x2)).Append(' ').Append(F(y2)).Append(" l S\n");

        public void Text(float x, float y, float size, bool bold, string text, bool white = false, bool muted = false)
        {
            var color = white ? "1 1 1" : muted ? "0.45 0.47 0.52" : "0.12 0.13 0.16";
            _page.Append("BT ").Append(color).Append(" rg /").Append(bold ? "F2" : "F1").Append(' ').Append(F(size))
                 .Append(" Tf ").Append(F(x)).Append(' ').Append(F(y)).Append(" Td (").Append(Escape(text)).Append(") Tj ET\n");
        }

        public void TextRight(float right, float y, float size, bool bold, string text, bool white = false) =>
            Text(right - Width(text, size, bold), y, size, bold, text, white);

        public byte[] Render()
        {
            var objects = new List<string>
            {
                "<< /Type /Catalog /Pages 2 0 R >>",
                "", // pages, filled below
                "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>",
                "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>",
            };

            var kids = new List<int>();
            for (var i = 0; i < _pages.Count; i++)
            {
                // Page footer: "Page n of m".
                if (_pages.Count > 1)
                {
                    var label = $"Page {i + 1} of {_pages.Count}";
                    _pages[i].Append("BT 0.45 0.47 0.52 rg /F1 8 Tf ")
                        .Append(F(PageWidth - Margin - Width(label, 8, false))).Append(" 28 Td (")
                        .Append(Escape(label)).Append(") Tj ET\n");
                }

                var content = _pages[i].ToString();
                var contentLength = Encoding.Latin1.GetByteCount(content);
                objects.Add($"<< /Length {contentLength} >>\nstream\n{content}endstream");
                var contentId = objects.Count;
                objects.Add($"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 {F(PageWidth)} {F(PageHeight)}] " +
                            $"/Resources << /Font << /F1 3 0 R /F2 4 0 R >> >> /Contents {contentId} 0 R >>");
                kids.Add(objects.Count);
            }
            objects[1] = $"<< /Type /Pages /Kids [{string.Join(' ', kids.Select(k => $"{k} 0 R"))}] /Count {kids.Count} >>";

            var sb = new StringBuilder("%PDF-1.4\n%âãÏÓ\n");
            var offsets = new List<int>();
            for (var i = 0; i < objects.Count; i++)
            {
                offsets.Add(Encoding.Latin1.GetByteCount(sb.ToString()));
                sb.Append(i + 1).Append(" 0 obj\n").Append(objects[i]).Append("\nendobj\n");
            }

            var xref = Encoding.Latin1.GetByteCount(sb.ToString());
            sb.Append("xref\n0 ").Append(objects.Count + 1).Append("\n0000000000 65535 f \n");
            foreach (var o in offsets) sb.Append(o.ToString("D10", CultureInfo.InvariantCulture)).Append(" 00000 n \n");
            sb.Append("trailer\n<< /Size ").Append(objects.Count + 1).Append(" /Root 1 0 R >>\nstartxref\n")
              .Append(xref).Append("\n%%EOF\n");

            return Encoding.Latin1.GetBytes(sb.ToString());
        }

        private static string F(float v) => v.ToString("0.##", CultureInfo.InvariantCulture);

        /// WinAnsi-safe: PDF string escapes, and anything outside Latin-1 as '?'.
        private static string Escape(string s)
        {
            var sb = new StringBuilder(s.Length);
            foreach (var ch in s)
            {
                var c = ch == '…' ? '.' : ch;
                if (c is '(' or ')' or '\\') sb.Append('\\').Append(c);
                else if (c < 32) sb.Append(' ');
                else if (c > 255) sb.Append('?');
                else sb.Append(c);
            }
            return sb.ToString();
        }

        // Helvetica advance widths (1/1000 em) for ASCII 32..126.
        private static readonly short[] HelveticaWidths =
        {
            278, 278, 355, 556, 556, 889, 667, 191, 333, 333, 389, 584, 278, 333, 278, 278,
            556, 556, 556, 556, 556, 556, 556, 556, 556, 556, 278, 278, 584, 584, 584, 556,
            1015, 667, 667, 722, 722, 667, 611, 778, 722, 278, 500, 667, 556, 833, 722, 778,
            667, 778, 722, 667, 611, 722, 667, 944, 667, 667, 611, 278, 278, 278, 469, 556,
            333, 556, 556, 500, 556, 556, 278, 556, 556, 222, 222, 500, 222, 833, 556, 556,
            556, 556, 333, 500, 278, 556, 500, 722, 500, 500, 500, 334, 260, 334, 584,
        };

        public static float Width(string text, float size, bool bold)
        {
            float units = 0;
            foreach (var c in text)
                units += c >= 32 && c <= 126 ? HelveticaWidths[c - 32] : 556;
            // Helvetica-Bold runs about 6% wider.
            return units * size / 1000f * (bold ? 1.06f : 1f);
        }
    }
}
