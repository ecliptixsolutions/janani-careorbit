import { createFileRoute } from "@tanstack/react-router";
import { useMemo, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { CreditCard, FileDown, Plus, ReceiptIndianRupee, Trash2 } from "lucide-react";
import { toast } from "sonner";
import { supabase } from "@/integrations/supabase/client";
import type { Json, Tables } from "@/integrations/supabase/types";
import { useAuth } from "@/hooks/use-auth";
import { useRoleAccess } from "@/hooks/use-role-access";
import { downloadInvoicePdf, jsonArray, money, type InvoiceLine } from "@/lib/clinical-operations";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";

export const Route = createFileRoute("/_authenticated/billing")({
  component: BillingPage,
});

type PatientMini = Pick<Tables<"patients">, "id" | "full_name" | "mrn">;
type InvoiceRow = Tables<"invoices"> & { patients: PatientMini | null };

function BillingPage() {
  const { user } = useAuth();
  const { data: access } = useRoleAccess();
  const qc = useQueryClient();
  const [invoiceOpen, setInvoiceOpen] = useState(false);
  const [paymentOpen, setPaymentOpen] = useState(false);
  const [selectedInvoice, setSelectedInvoice] = useState<InvoiceRow | null>(null);
  const [patientId, setPatientId] = useState("");
  const [lines, setLines] = useState<InvoiceLine[]>([
    { description: "Consultation", quantity: 1, unitPrice: 0 },
  ]);
  const [discount, setDiscount] = useState("0");
  const [tax, setTax] = useState("0");
  const [notes, setNotes] = useState("");
  const [paymentAmount, setPaymentAmount] = useState("");
  const [paymentMethod, setPaymentMethod] = useState("cash");
  const [paymentReference, setPaymentReference] = useState("");

  const canManage =
    access?.permissions.canAccessBilling || access?.permissions.canManageUsers || false;

  const { data: patients = [] } = useQuery<PatientMini[]>({
    queryKey: ["clinical-patients"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("patients")
        .select("id, full_name, mrn")
        .order("full_name");
      if (error) throw error;
      return data ?? [];
    },
  });

  const { data: invoices = [], isLoading } = useQuery<InvoiceRow[]>({
    queryKey: ["invoices"],
    enabled: canManage,
    queryFn: async () => {
      const { data, error } = await supabase
        .from("invoices")
        .select("*, patients(id, full_name, mrn)")
        .order("created_at", { ascending: false });
      if (error) throw error;
      return (data ?? []) as InvoiceRow[];
    },
  });

  const subtotal = useMemo(
    () => lines.reduce((total, line) => total + line.quantity * line.unitPrice, 0),
    [lines],
  );
  const total = Math.max(subtotal - Number(discount || 0) + Number(tax || 0), 0);

  const createInvoice = useMutation({
    mutationFn: async () => {
      const validLines = lines.filter((line) => line.description.trim() && line.quantity > 0);
      if (!patientId || validLines.length === 0)
        throw new Error("Patient and invoice items are required");
      const { error } = await supabase.from("invoices").insert({
        patient_id: patientId,
        items: validLines as unknown as Json,
        subtotal,
        discount_amount: Number(discount || 0),
        tax_amount: Number(tax || 0),
        total_amount: total,
        notes,
        status: "issued",
        created_by: user!.id,
      });
      if (error) throw error;
    },
    onSuccess: () => {
      toast.success("Invoice created");
      qc.invalidateQueries({ queryKey: ["invoices"] });
      setInvoiceOpen(false);
      setPatientId("");
      setLines([{ description: "Consultation", quantity: 1, unitPrice: 0 }]);
      setDiscount("0");
      setTax("0");
      setNotes("");
    },
    onError: (error: Error) => toast.error(error.message),
  });

  const recordPayment = useMutation({
    mutationFn: async () => {
      if (!selectedInvoice) throw new Error("Select an invoice");
      const amount = Number(paymentAmount);
      const balance = Number(selectedInvoice.total_amount) - Number(selectedInvoice.paid_amount);
      if (!amount || amount <= 0 || amount > balance)
        throw new Error("Enter an amount within the balance");
      const { error } = await supabase.rpc("record_invoice_payment", {
        _invoice_id: selectedInvoice.id,
        _amount: amount,
        _method: paymentMethod,
        _reference: paymentReference,
      });
      if (error) throw error;
    },
    onSuccess: () => {
      toast.success("Payment recorded");
      qc.invalidateQueries({ queryKey: ["invoices"] });
      setPaymentOpen(false);
      setSelectedInvoice(null);
      setPaymentAmount("");
      setPaymentReference("");
    },
    onError: (error: Error) => toast.error(error.message),
  });

  if (!canManage) {
    return (
      <div className="rounded-lg border bg-card p-8 text-center">
        <ReceiptIndianRupee className="mx-auto h-10 w-10 text-muted-foreground" />
        <h1 className="mt-4 text-2xl font-bold">Billing restricted</h1>
        <p className="mt-2 text-sm text-muted-foreground">
          Billing is available to billing operators and administrators.
        </p>
      </div>
    );
  }

  const updateLine = (index: number, key: keyof InvoiceLine, value: string) => {
    setLines((current) =>
      current.map((line, lineIndex) =>
        lineIndex === index
          ? { ...line, [key]: key === "description" ? value : Number(value) }
          : line,
      ),
    );
  };

  const openPayment = (invoice: InvoiceRow) => {
    setSelectedInvoice(invoice);
    setPaymentAmount(
      String(Math.max(Number(invoice.total_amount) - Number(invoice.paid_amount), 0)),
    );
    setPaymentOpen(true);
  };

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="text-3xl font-bold">Billing & payments</h1>
          <p className="mt-1 text-muted-foreground">
            Create itemized invoices, collect payments and issue PDF receipts.
          </p>
        </div>
        <Dialog open={invoiceOpen} onOpenChange={setInvoiceOpen}>
          <DialogTrigger asChild>
            <Button className="bg-gradient-brand text-white">
              <Plus className="mr-2 h-4 w-4" /> New invoice
            </Button>
          </DialogTrigger>
          <DialogContent className="max-h-[calc(100vh-2rem)] overflow-y-auto sm:max-w-3xl">
            <DialogHeader>
              <DialogTitle>Create invoice</DialogTitle>
              <DialogDescription>Add billable services, discounts and tax.</DialogDescription>
            </DialogHeader>
            <div className="space-y-4">
              <div>
                <Label>Patient</Label>
                <Select value={patientId} onValueChange={setPatientId}>
                  <SelectTrigger>
                    <SelectValue placeholder="Select patient" />
                  </SelectTrigger>
                  <SelectContent>
                    {patients.map((patient) => (
                      <SelectItem key={patient.id} value={patient.id}>
                        {patient.full_name} ({patient.mrn})
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
              <div className="space-y-2">
                <div className="flex items-center justify-between">
                  <Label>Invoice items</Label>
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={() =>
                      setLines((current) => [
                        ...current,
                        { description: "", quantity: 1, unitPrice: 0 },
                      ])
                    }
                  >
                    <Plus className="mr-1 h-4 w-4" /> Add item
                  </Button>
                </div>
                {lines.map((line, index) => (
                  <div
                    key={index}
                    className="grid gap-2 rounded-lg border p-3 sm:grid-cols-[1fr_100px_140px_auto]"
                  >
                    <Input
                      value={line.description}
                      onChange={(event) => updateLine(index, "description", event.target.value)}
                      placeholder="Service or item"
                    />
                    <Input
                      type="number"
                      min={1}
                      value={line.quantity}
                      onChange={(event) => updateLine(index, "quantity", event.target.value)}
                    />
                    <Input
                      type="number"
                      min={0}
                      step="0.01"
                      value={line.unitPrice}
                      onChange={(event) => updateLine(index, "unitPrice", event.target.value)}
                    />
                    <Button
                      variant="ghost"
                      size="icon"
                      disabled={lines.length === 1}
                      onClick={() =>
                        setLines((current) => current.filter((_, lineIndex) => lineIndex !== index))
                      }
                    >
                      <Trash2 className="h-4 w-4" />
                    </Button>
                  </div>
                ))}
              </div>
              <div className="grid gap-3 sm:grid-cols-3">
                <div>
                  <Label>Subtotal</Label>
                  <Input value={money(subtotal)} disabled />
                </div>
                <div>
                  <Label>Discount</Label>
                  <Input
                    type="number"
                    min={0}
                    value={discount}
                    onChange={(event) => setDiscount(event.target.value)}
                  />
                </div>
                <div>
                  <Label>Tax</Label>
                  <Input
                    type="number"
                    min={0}
                    value={tax}
                    onChange={(event) => setTax(event.target.value)}
                  />
                </div>
              </div>
              <div className="rounded-lg border bg-muted/30 p-3 text-right text-lg font-semibold">
                Total: {money(total)}
              </div>
              <div>
                <Label>Notes</Label>
                <Textarea value={notes} onChange={(event) => setNotes(event.target.value)} />
              </div>
            </div>
            <DialogFooter>
              <Button
                onClick={() => createInvoice.mutate()}
                disabled={createInvoice.isPending || !patientId}
                className="bg-gradient-brand text-white"
              >
                {createInvoice.isPending ? "Creating..." : "Create invoice"}
              </Button>
            </DialogFooter>
          </DialogContent>
        </Dialog>
      </div>

      {isLoading ? (
        <div className="py-12 text-center text-sm text-muted-foreground">Loading...</div>
      ) : invoices.length === 0 ? (
        <div className="rounded-lg border border-dashed p-10 text-center text-muted-foreground">
          No invoices created yet.
        </div>
      ) : (
        <div className="grid gap-3">
          {invoices.map((invoice) => {
            const invoiceLines = jsonArray<InvoiceLine>(invoice.items);
            const balance = Math.max(Number(invoice.total_amount) - Number(invoice.paid_amount), 0);
            return (
              <div
                key={invoice.id}
                className="grid gap-4 rounded-lg border bg-card p-4 lg:grid-cols-[1fr_auto]"
              >
                <div>
                  <div className="flex flex-wrap items-center gap-2">
                    <h2 className="font-semibold">{invoice.invoice_number}</h2>
                    <Badge variant="secondary">{invoice.status.replace("_", " ")}</Badge>
                  </div>
                  <div className="mt-1 text-sm text-muted-foreground">
                    {invoice.patients?.full_name} · {invoice.patients?.mrn}
                  </div>
                  <div className="mt-3 flex flex-wrap gap-5 text-sm">
                    <span>
                      Total: <strong>{money(invoice.total_amount)}</strong>
                    </span>
                    <span>
                      Paid: <strong>{money(invoice.paid_amount)}</strong>
                    </span>
                    <span>
                      Balance: <strong>{money(balance)}</strong>
                    </span>
                  </div>
                </div>
                <div className="flex flex-wrap items-center gap-2">
                  {balance > 0 && (
                    <Button variant="outline" onClick={() => openPayment(invoice)}>
                      <CreditCard className="mr-2 h-4 w-4" /> Record payment
                    </Button>
                  )}
                  <Button
                    variant="outline"
                    onClick={() =>
                      downloadInvoicePdf({
                        invoiceNumber: invoice.invoice_number,
                        patientName: invoice.patients?.full_name ?? "Patient",
                        mrn: invoice.patients?.mrn ?? "",
                        items: invoiceLines,
                        subtotal: Number(invoice.subtotal),
                        discount: Number(invoice.discount_amount),
                        tax: Number(invoice.tax_amount),
                        total: Number(invoice.total_amount),
                        paid: Number(invoice.paid_amount),
                      })
                    }
                  >
                    <FileDown className="mr-2 h-4 w-4" /> PDF
                  </Button>
                </div>
              </div>
            );
          })}
        </div>
      )}

      <Dialog open={paymentOpen} onOpenChange={setPaymentOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Record payment</DialogTitle>
            <DialogDescription>{selectedInvoice?.invoice_number}</DialogDescription>
          </DialogHeader>
          <div className="space-y-4">
            <div>
              <Label>Amount</Label>
              <Input
                type="number"
                min={0.01}
                step="0.01"
                value={paymentAmount}
                onChange={(event) => setPaymentAmount(event.target.value)}
              />
            </div>
            <div>
              <Label>Method</Label>
              <Select value={paymentMethod} onValueChange={setPaymentMethod}>
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {["cash", "card", "upi", "bank_transfer", "insurance", "other"].map((method) => (
                    <SelectItem key={method} value={method}>
                      {method.replace("_", " ")}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div>
              <Label>Reference</Label>
              <Input
                value={paymentReference}
                onChange={(event) => setPaymentReference(event.target.value)}
              />
            </div>
          </div>
          <DialogFooter>
            <Button
              onClick={() => recordPayment.mutate()}
              disabled={recordPayment.isPending}
              className="bg-gradient-brand text-white"
            >
              {recordPayment.isPending ? "Recording..." : "Record payment"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
