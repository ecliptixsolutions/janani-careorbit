import type { Json } from "@/integrations/supabase/types";

export type MedicineLine = {
  name: string;
  dosage: string;
  frequency: string;
  duration: string;
  instructions: string;
};

export type InvoiceLine = {
  description: string;
  quantity: number;
  unitPrice: number;
};

export function jsonArray<T>(value: Json): T[] {
  return Array.isArray(value) ? (value as T[]) : [];
}

export function money(value: number | string | null | undefined) {
  return new Intl.NumberFormat("en-IN", {
    style: "currency",
    currency: "INR",
    maximumFractionDigits: 2,
  }).format(Number(value ?? 0));
}

export function downloadBlob(filename: string, blob: Blob) {
  const href = URL.createObjectURL(blob);
  const anchor = document.createElement("a");
  anchor.href = href;
  anchor.download = filename;
  anchor.style.display = "none";
  document.body.appendChild(anchor);
  anchor.click();
  anchor.remove();
  window.setTimeout(() => URL.revokeObjectURL(href), 1000);
}

export function downloadJson(filename: string, value: unknown) {
  const blob = new Blob([JSON.stringify(value, null, 2)], { type: "application/json" });
  downloadBlob(filename, blob);
}

export async function downloadExcel(
  filename: string,
  sheets: Array<{ name: string; rows: Record<string, unknown>[] }>,
) {
  const { default: writeXlsxFile } = await import("write-excel-file/browser");
  const workbookSheets = sheets.map(({ name, rows }) => {
    const keys = Array.from(new Set(rows.flatMap((row) => Object.keys(row))));
    const data = [
      keys.map((key) => ({
        value: key,
        fontWeight: "bold" as const,
        textColor: "#FFFFFF",
        backgroundColor: "#0F766E",
      })),
      ...rows.map((row) =>
        keys.map((key) => {
          const value = row[key];
          if (value == null) return "";
          if (
            typeof value === "string" ||
            typeof value === "number" ||
            typeof value === "boolean"
          ) {
            return value;
          }
          if (value instanceof Date) return value;
          return JSON.stringify(value);
        }),
      ),
    ];
    return {
      data,
      sheet: name.slice(0, 31),
      columns: keys.map((key) => ({
        width: Math.min(
          40,
          Math.max(key.length + 2, ...rows.map((row) => String(row[key] ?? "").length + 2)),
        ),
      })),
      stickyRowsCount: keys.length ? 1 : 0,
    };
  });

  const blob = await writeXlsxFile(workbookSheets).toBlob();
  downloadBlob(filename, blob);
}

export async function downloadPrescriptionPdf(input: {
  prescriptionNumber: string;
  patientName: string;
  mrn: string;
  doctorName: string;
  diagnosis: string;
  advice: string;
  medicines: MedicineLine[];
  issuedAt: string;
}) {
  const { jsPDF } = await import("jspdf");
  const pdf = new jsPDF();
  const left = 18;
  let y = 20;

  pdf.setFont("helvetica", "bold");
  pdf.setFontSize(20);
  pdf.text("CareOrbit Prescription", left, y);
  pdf.setFontSize(10);
  pdf.setFont("helvetica", "normal");
  y += 9;
  pdf.text(`Prescription: ${input.prescriptionNumber}`, left, y);
  pdf.text(`Issued: ${new Date(input.issuedAt).toLocaleString()}`, 120, y);
  y += 10;
  pdf.line(left, y, 192, y);
  y += 8;
  pdf.text(`Patient: ${input.patientName}`, left, y);
  pdf.text(`MRN: ${input.mrn}`, 120, y);
  y += 7;
  pdf.text(`Doctor: ${input.doctorName}`, left, y);
  y += 10;
  pdf.setFont("helvetica", "bold");
  pdf.text("Diagnosis", left, y);
  pdf.setFont("helvetica", "normal");
  y += 6;
  pdf.text(pdf.splitTextToSize(input.diagnosis || "Not specified", 174), left, y);
  y += 12;
  pdf.setFont("helvetica", "bold");
  pdf.text("Medicines", left, y);
  y += 7;

  input.medicines.forEach((medicine, index) => {
    if (y > 265) {
      pdf.addPage();
      y = 20;
    }
    pdf.setFont("helvetica", "bold");
    pdf.text(`${index + 1}. ${medicine.name}`, left, y);
    pdf.setFont("helvetica", "normal");
    y += 6;
    const details = [medicine.dosage, medicine.frequency, medicine.duration, medicine.instructions]
      .filter(Boolean)
      .join(" | ");
    pdf.text(pdf.splitTextToSize(details || "As directed", 168), left + 5, y);
    y += 10;
  });

  pdf.setFont("helvetica", "bold");
  pdf.text("Advice", left, y);
  pdf.setFont("helvetica", "normal");
  y += 6;
  pdf.text(
    pdf.splitTextToSize(input.advice || "Follow the prescribed treatment plan.", 174),
    left,
    y,
  );
  downloadBlob(`${input.prescriptionNumber}.pdf`, pdf.output("blob"));
}

export async function downloadInvoicePdf(input: {
  invoiceNumber: string;
  patientName: string;
  mrn: string;
  items: InvoiceLine[];
  subtotal: number;
  discount: number;
  tax: number;
  total: number;
  paid: number;
}) {
  const { jsPDF } = await import("jspdf");
  const pdf = new jsPDF();
  let y = 20;
  pdf.setFont("helvetica", "bold");
  pdf.setFontSize(20);
  pdf.text("CareOrbit Invoice", 18, y);
  pdf.setFontSize(10);
  pdf.setFont("helvetica", "normal");
  y += 9;
  pdf.text(`Invoice: ${input.invoiceNumber}`, 18, y);
  y += 7;
  pdf.text(`Patient: ${input.patientName} (${input.mrn})`, 18, y);
  y += 10;
  pdf.line(18, y, 192, y);
  y += 8;

  input.items.forEach((item, index) => {
    pdf.text(`${index + 1}. ${item.description}`, 18, y);
    pdf.text(`${item.quantity} x ${money(item.unitPrice)}`, 118, y);
    pdf.text(money(item.quantity * item.unitPrice), 166, y);
    y += 7;
  });

  y += 5;
  pdf.line(118, y, 192, y);
  y += 7;
  [
    ["Subtotal", input.subtotal],
    ["Discount", -input.discount],
    ["Tax", input.tax],
    ["Total", input.total],
    ["Paid", input.paid],
    ["Balance", Math.max(input.total - input.paid, 0)],
  ].forEach(([label, value]) => {
    pdf.text(String(label), 120, y);
    pdf.text(money(Number(value)), 166, y);
    y += 7;
  });
  downloadBlob(`${input.invoiceNumber}.pdf`, pdf.output("blob"));
}
