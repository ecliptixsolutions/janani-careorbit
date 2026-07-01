import { createFileRoute } from "@tanstack/react-router";
import { useMemo, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { CalendarDays, Clock3, Plus, QrCode, Stethoscope } from "lucide-react";
import { toast } from "sonner";
import { format } from "date-fns";
import { supabase } from "@/integrations/supabase/client";
import type { Tables, TablesInsert } from "@/integrations/supabase/types";
import { useAuth } from "@/hooks/use-auth";
import { useRoleAccess } from "@/hooks/use-role-access";
import {
  buildAppointmentNotes,
  formatAppointmentWindow,
  getAppointmentDoctorName,
  getAppointmentToken,
} from "@/lib/appointment-workflow";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
  DialogFooter,
} from "@/components/ui/dialog";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Badge } from "@/components/ui/badge";

export const Route = createFileRoute("/_authenticated/appointments")({
  component: AppointmentsPage,
});

type AppointmentStatus = Tables<"appointments">["status"];
type PatientOption = Pick<Tables<"patients">, "id" | "full_name" | "mrn" | "phone">;
type AppointmentWithPatient = Tables<"appointments"> & {
  patients: PatientOption | null;
};
type AppointmentFormValues = {
  patient_id: string;
  appointment_date: string;
  appointment_time: string;
  duration_minutes: string;
  doctor_name: string;
  reason: string;
  visit_notes: string;
  status: AppointmentStatus;
};
type AppointmentCreatePayload = TablesInsert<"appointments">;

const statusColors: Record<AppointmentStatus, string> = {
  scheduled: "bg-blue-500/10 text-blue-700 dark:text-blue-300",
  confirmed: "bg-emerald-500/10 text-emerald-700 dark:text-emerald-300",
  completed: "bg-gray-500/10 text-gray-700 dark:text-gray-300",
  cancelled: "bg-red-500/10 text-red-700 dark:text-red-300",
  no_show: "bg-orange-500/10 text-orange-700 dark:text-orange-300",
};

function todayInputDate() {
  return new Date().toISOString().slice(0, 10);
}

function AppointmentsPage() {
  const { user } = useAuth();
  const { data: access } = useRoleAccess();
  const qc = useQueryClient();
  const [open, setOpen] = useState(false);

  const { data: appts = [], isLoading } = useQuery<AppointmentWithPatient[]>({
    queryKey: ["appointments"],
    queryFn: async () => {
      const { data, error } = await supabase
        .from("appointments")
        .select("*, patients(id, full_name, mrn, phone)")
        .order("scheduled_at", { ascending: true });
      if (error) throw error;
      return (data ?? []) as AppointmentWithPatient[];
    },
  });

  const { data: patients = [] } = useQuery<PatientOption[]>({
    queryKey: ["patients-list"],
    queryFn: async () => {
      const { data } = await supabase
        .from("patients")
        .select("id, full_name, mrn, phone")
        .order("full_name");
      return (data ?? []) as PatientOption[];
    },
  });

  const todayAppointments = useMemo(() => {
    const today = todayInputDate();
    return appts.filter((appointment) => appointment.scheduled_at.slice(0, 10) === today);
  }, [appts]);

  const createMut = useMutation<void, Error, AppointmentCreatePayload>({
    mutationFn: async (form) => {
      const { error } = await supabase.from("appointments").insert({
        ...form,
        doctor_id: user!.id,
        created_by: user!.id,
      });
      if (error) throw error;
    },
    onSuccess: () => {
      toast.success("Appointment scheduled");
      qc.invalidateQueries({ queryKey: ["appointments"] });
      setOpen(false);
    },
    onError: (e) => toast.error(e.message),
  });

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="text-3xl font-bold tracking-tight">Appointments</h1>
          <p className="mt-1 text-muted-foreground">
            Schedule consultations with doctor name, date, time, duration, and queue context.
          </p>
          <div className="mt-2 flex flex-wrap items-center gap-2 text-xs text-muted-foreground">
            <Badge variant="secondary">{access?.copy.label ?? "Role"}</Badge>
            <span>
              {access?.permissions.canScheduleAppointments
                ? "Can create appointments under current role rights."
                : "Appointment scheduling is not available for this role."}
            </span>
          </div>
        </div>
        <Dialog open={open} onOpenChange={setOpen}>
          <DialogTrigger asChild>
            <Button
              className="bg-gradient-brand text-white hover:opacity-90"
              disabled={
                patients.length === 0 || !(access?.permissions.canScheduleAppointments ?? true)
              }
            >
              <Plus className="mr-2 h-4 w-4" /> New appointment
            </Button>
          </DialogTrigger>
          <DialogContent className="sm:max-w-2xl">
            <DialogHeader>
              <DialogTitle>New appointment</DialogTitle>
              <DialogDescription>
                Select a patient, doctor, appointment date, appointment time, duration, and problem
                brief.
              </DialogDescription>
            </DialogHeader>
            <ApptForm
              patients={patients}
              loading={createMut.isPending}
              queuePosition={todayAppointments.length + 1}
              onSubmit={(d) => createMut.mutate(d)}
            />
          </DialogContent>
        </Dialog>
      </div>

      <div className="grid gap-4 md:grid-cols-3">
        <div className="rounded-xl border bg-gradient-card p-5">
          <div className="flex items-center gap-2 text-sm text-muted-foreground">
            <CalendarDays className="h-4 w-4 text-brand-blue" />
            Today's schedule
          </div>
          <div className="mt-3 text-3xl font-bold">{todayAppointments.length}</div>
        </div>
        <div className="rounded-xl border bg-gradient-card p-5">
          <div className="flex items-center gap-2 text-sm text-muted-foreground">
            <Clock3 className="h-4 w-4 text-brand-red" />
            Default slot
          </div>
          <div className="mt-3 text-3xl font-bold">30 min</div>
        </div>
        <div className="rounded-xl border bg-gradient-card p-5">
          <div className="flex items-center gap-2 text-sm text-muted-foreground">
            <QrCode className="h-4 w-4 text-brand-blue" />
            Queue tokens
          </div>
          <div className="mt-3 text-3xl font-bold">Auto</div>
        </div>
      </div>

      {patients.length === 0 && (
        <div className="rounded-lg border border-dashed bg-muted/30 p-4 text-sm text-muted-foreground">
          Add a patient first to schedule appointments.
        </div>
      )}

      <div className="overflow-hidden rounded-xl border bg-card">
        {isLoading ? (
          <div className="p-12 text-center text-sm text-muted-foreground">Loading...</div>
        ) : appts.length === 0 ? (
          <div className="p-12 text-center">
            <CalendarDays className="mx-auto h-10 w-10 text-muted-foreground/50" />
            <p className="mt-3 text-sm text-muted-foreground">No appointments yet.</p>
          </div>
        ) : (
          <table className="w-full text-sm">
            <thead className="bg-muted/50 text-left text-xs uppercase tracking-wide text-muted-foreground">
              <tr>
                <th className="px-4 py-3">Date / time</th>
                <th className="px-4 py-3">Patient</th>
                <th className="px-4 py-3 hidden lg:table-cell">Doctor</th>
                <th className="px-4 py-3 hidden md:table-cell">Problem / disease brief</th>
                <th className="px-4 py-3 hidden lg:table-cell">Queue</th>
                <th className="px-4 py-3">Status</th>
              </tr>
            </thead>
            <tbody>
              {appts.map((appointment, index) => (
                <tr key={appointment.id} className="border-t hover:bg-muted/30">
                  <td className="px-4 py-3 font-medium">
                    {format(new Date(appointment.scheduled_at), "MMM d, yyyy")}
                    <div className="text-xs text-muted-foreground">
                      {format(new Date(appointment.scheduled_at), "h:mm a")} ·{" "}
                      {appointment.duration_minutes} min
                    </div>
                  </td>
                  <td className="px-4 py-3">
                    {appointment.patients?.full_name}
                    <div className="font-mono text-xs text-muted-foreground">
                      {appointment.patients?.mrn}
                    </div>
                  </td>
                  <td className="px-4 py-3 hidden lg:table-cell">
                    <div className="flex items-center gap-2">
                      <Stethoscope className="h-4 w-4 text-brand-blue" />
                      {getAppointmentDoctorName(appointment)}
                    </div>
                  </td>
                  <td className="px-4 py-3 hidden max-w-xs md:table-cell text-muted-foreground">
                    {appointment.reason || "-"}
                    <div className="mt-1 text-xs">{formatAppointmentWindow(appointment)}</div>
                  </td>
                  <td className="px-4 py-3 hidden lg:table-cell">
                    <Badge variant="outline">{getAppointmentToken(appointment, index)}</Badge>
                  </td>
                  <td className="px-4 py-3">
                    <Badge variant="secondary" className={statusColors[appointment.status]}>
                      {appointment.status}
                    </Badge>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  );
}

function ApptForm({
  patients,
  onSubmit,
  loading,
  queuePosition,
}: {
  patients: PatientOption[];
  onSubmit: (d: AppointmentCreatePayload) => void;
  loading: boolean;
  queuePosition: number;
}) {
  const [form, setForm] = useState<AppointmentFormValues>({
    patient_id: "",
    appointment_date: todayInputDate(),
    appointment_time: "",
    duration_minutes: "30",
    doctor_name: "",
    reason: "",
    visit_notes: "",
    status: "scheduled",
  });
  const update = <K extends keyof AppointmentFormValues>(k: K, v: AppointmentFormValues[K]) =>
    setForm({ ...form, [k]: v });

  return (
    <form
      onSubmit={(e) => {
        e.preventDefault();
        const scheduledAt = new Date(`${form.appointment_date}T${form.appointment_time}`);
        onSubmit({
          patient_id: form.patient_id,
          scheduled_at: scheduledAt.toISOString(),
          duration_minutes: Number(form.duration_minutes),
          reason: form.reason,
          status: form.status,
          notes: buildAppointmentNotes(form.visit_notes, {
            doctorName: form.doctor_name,
            token: `Q-${form.appointment_date.replaceAll("-", "").slice(4)}-${String(
              queuePosition,
            ).padStart(3, "0")}`,
            prescriptionPdf: "Pending",
            labReport: "Pending",
            medicineReminder: "Not scheduled",
          }),
        });
      }}
      className="space-y-4"
    >
      <div>
        <Label>Patient *</Label>
        <Select value={form.patient_id} onValueChange={(v) => update("patient_id", v)}>
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
      <div>
        <Label>Doctor name *</Label>
        <Input
          required
          value={form.doctor_name}
          onChange={(e) => update("doctor_name", e.target.value)}
          placeholder="e.g. Dr Shah"
        />
      </div>
      <div className="grid gap-3 sm:grid-cols-3">
        <div>
          <Label>Appointment date *</Label>
          <Input
            type="date"
            required
            value={form.appointment_date}
            onChange={(e) => update("appointment_date", e.target.value)}
          />
        </div>
        <div>
          <Label>Appointment time *</Label>
          <Input
            type="time"
            required
            value={form.appointment_time}
            onChange={(e) => update("appointment_time", e.target.value)}
          />
        </div>
        <div>
          <Label>Duration (min)</Label>
          <Input
            type="number"
            min={5}
            step={5}
            value={form.duration_minutes}
            onChange={(e) => update("duration_minutes", e.target.value)}
          />
        </div>
      </div>
      <div>
        <Label>Patient problem / disease brief</Label>
        <Textarea
          rows={3}
          value={form.reason}
          onChange={(e) => update("reason", e.target.value)}
          placeholder="e.g. Fever for 3 days, diabetes follow-up, post-surgery review"
        />
      </div>
      <div>
        <Label>Internal appointment notes</Label>
        <Textarea
          rows={2}
          value={form.visit_notes}
          onChange={(e) => update("visit_notes", e.target.value)}
          placeholder="Optional reception or clinical notes"
        />
      </div>
      <DialogFooter>
        <Button
          type="submit"
          disabled={loading || !form.patient_id || !form.appointment_time || !form.doctor_name}
          className="bg-gradient-brand text-white hover:opacity-90"
        >
          {loading ? "Saving..." : "Schedule appointment"}
        </Button>
      </DialogFooter>
    </form>
  );
}
