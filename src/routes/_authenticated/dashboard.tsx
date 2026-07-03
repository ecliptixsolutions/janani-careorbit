import { createFileRoute } from "@tanstack/react-router";
import { useQuery } from "@tanstack/react-query";
import {
  Activity,
  BellRing,
  CalendarDays,
  CheckCircle2,
  ClipboardList,
  FlaskConical,
  ListOrdered,
  MessageCircle,
  Pill,
  Receipt,
  ShieldCheck,
  TrendingUp,
  Users,
} from "lucide-react";
import type { LucideIcon } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { useRoleAccess } from "@/hooks/use-role-access";
import { Badge } from "@/components/ui/badge";
import { isMissingRelationError } from "@/lib/supabase-errors";

export const Route = createFileRoute("/_authenticated/dashboard")({
  component: Dashboard,
});

function Dashboard() {
  const { data: access } = useRoleAccess();

  const { data: stats } = useQuery({
    queryKey: ["dashboard-stats"],
    queryFn: async () => {
      const [patients, appts, today] = await Promise.all([
        supabase.from("patients").select("*", { count: "exact", head: true }),
        supabase.from("appointments").select("*", { count: "exact", head: true }),
        supabase
          .from("appointments")
          .select("*", { count: "exact", head: true })
          .gte("scheduled_at", new Date(new Date().setHours(0, 0, 0, 0)).toISOString())
          .lt("scheduled_at", new Date(new Date().setHours(24, 0, 0, 0)).toISOString()),
      ]);

      if (patients.error && !isMissingRelationError(patients.error)) throw patients.error;
      if (appts.error && !isMissingRelationError(appts.error)) throw appts.error;
      if (today.error && !isMissingRelationError(today.error)) throw today.error;

      return {
        patients: patients.count ?? 0,
        appts: appts.count ?? 0,
        today: today.count ?? 0,
      };
    },
  });

  const cards = [
    {
      label: "Total patients",
      value: stats?.patients ?? 0,
      icon: Users,
      accent: "text-brand-blue",
    },
    {
      label: "Total appointments",
      value: stats?.appts ?? 0,
      icon: CalendarDays,
      accent: "text-brand-red",
    },
    {
      label: "Today's appointments",
      value: stats?.today ?? 0,
      icon: Activity,
      accent: "text-brand-blue",
    },
    { label: "Active modules", value: 16, icon: TrendingUp, accent: "text-brand-red" },
  ];

  const roleDashboards: Record<
    string,
    { title: string; widgets: Array<[string, string, LucideIcon]> }
  > = {
    super_admin: {
      title: "Super Admin dashboard",
      widgets: [
        ["Hospitals & admins", "Approve hospital admins and monitor all roles.", ShieldCheck],
        ["Automation coverage", "Review WhatsApp, queue, EMR, and module readiness.", TrendingUp],
        ["Access governance", "Audit high-right users and pending approvals.", Users],
      ],
    },
    hospital_admin: {
      title: "Hospital Admin dashboard",
      widgets: [
        [
          "Today's operations",
          `${stats?.today ?? 0} appointments need facility tracking.`,
          Activity,
        ],
        ["Reception queue", "Monitor check-ins, waiting time, and token flow.", ListOrdered],
        [
          "User approval",
          "Approve doctors, nurses, lab, pharmacy, and billing users.",
          ShieldCheck,
        ],
      ],
    },
    admin: {
      title: "Admin dashboard",
      widgets: [
        ["Access control", "Approve accounts and assign role-wise rights.", ShieldCheck],
        ["Follow-up CRM", "Track reminder and missed appointment recovery work.", BellRing],
        [
          "Clinic volume",
          `${stats?.patients ?? 0} patients and ${stats?.appts ?? 0} appointments.`,
          TrendingUp,
        ],
      ],
    },
    doctor: {
      title: "Doctor dashboard",
      widgets: [
        ["Patient timeline", "Open Smart EMR history before consultation.", ClipboardList],
        ["Appointments", "Review upcoming visits and problem briefs.", CalendarDays],
        ["Queue", "See current token and expected waiting time.", ListOrdered],
      ],
    },
    staff: {
      title: "Reception dashboard",
      widgets: [
        ["Token queue", "Check in patients with QR or reception lookup.", ListOrdered],
        [
          "New appointment",
          "Schedule date, time, duration, doctor, and problem brief.",
          CalendarDays,
        ],
        [
          "WhatsApp reminders",
          "Prepare appointment reminders and recovery messages.",
          MessageCircle,
        ],
      ],
    },
    nurse: {
      title: "Nurse dashboard",
      widgets: [
        ["Vitals ready", "Use EMR timeline to support vitals capture workflow.", Activity],
        ["Queue support", "Assist checked-in patients and doctor handoff.", ListOrdered],
        ["Patient context", "Review history and clinical notes before care.", ClipboardList],
      ],
    },
    pharmacist: {
      title: "Pharmacy dashboard",
      widgets: [
        ["Prescription queue", "Review prescription status from completed visits.", Pill],
        ["Medicine reminders", "Prepare WhatsApp medicine reminder messages.", MessageCircle],
        ["Patient context", "Open EMR timeline for prescription history.", ClipboardList],
      ],
    },
    lab_technician: {
      title: "Lab dashboard",
      widgets: [
        ["Lab reports", "Review linked lab report workflow status.", FlaskConical],
        ["Patient context", "Search EMR timeline and appointment problem brief.", ClipboardList],
        ["Report messages", "Prepare lab report WhatsApp notifications.", MessageCircle],
      ],
    },
    billing_operator: {
      title: "Billing dashboard",
      widgets: [
        ["Billing timeline", "Review completed appointment billing context.", Receipt],
        ["Visit duration", "Use duration and appointment data for billing.", CalendarDays],
        ["Patient lookup", "Find patient records for invoice support.", Users],
      ],
    },
    custom: {
      title: "Custom role dashboard",
      widgets: [
        ["Assigned rights", "Use the modules allowed by admin role setup.", ShieldCheck],
        ["Appointments", "View available appointment workflow context.", CalendarDays],
        ["Patients", "Access patient screens when permitted.", Users],
      ],
    },
    pending: {
      title: "Pending approval dashboard",
      widgets: [
        ["Approval required", "Wait for admin approval before module access.", ShieldCheck],
        ["Requested access", "Your requested role is visible to admin.", Users],
        ["Next step", "Contact hospital admin if urgent.", BellRing],
      ],
    },
  };
  const roleDashboard = roleDashboards[access?.roleKey ?? "custom"] ?? roleDashboards.custom;

  const rights = [
    ["Patients", access?.permissions.canViewPatients, "View patient records"],
    ["History", access?.permissions.canViewPatientHistory, "Search patient history by number"],
    ["Add Patient", access?.permissions.canCreatePatients, "Register patients and assign doctors"],
    [
      "Appointments",
      access?.permissions.canScheduleAppointments,
      "Schedule consultations and problem briefs",
    ],
    ["Queue", access?.permissions.canViewQueue, "Live token queue and QR check-in"],
    ["EMR Timeline", access?.permissions.canViewEmrTimeline, "Modern full patient history view"],
    ["Automations", access?.permissions.canManageAutomations, "WhatsApp reminders and follow-ups"],
    ["Modules", access?.permissions.canViewModules, "Open enabled ERP module workspaces"],
    ["User Approval", access?.permissions.canApproveUsers, "Approve accounts and assign roles"],
    ["Role Creation", access?.permissions.canManageRoles, "Create role templates and rights"],
    ["Delete Rights", access?.permissions.canDeleteRecords, "Delete/manage when UI exists"],
  ] as const;

  return (
    <div className="space-y-8">
      <div>
        <h1 className="text-3xl font-bold tracking-tight">
          Welcome
          {access?.profile?.full_name ? `, ${access.profile.full_name.split(" ")[0]}` : ""}
        </h1>
        <p className="mt-1 text-muted-foreground">
          {access?.profile?.organization || "Your facility"} - here's a quick snapshot.
        </p>
      </div>

      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        {cards.map((c) => (
          <div key={c.label} className="rounded-xl border bg-gradient-card p-6 shadow-sm">
            <div className="flex items-center justify-between">
              <span className="text-sm text-muted-foreground">{c.label}</span>
              <c.icon className={`h-5 w-5 ${c.accent}`} />
            </div>
            <div className="mt-4 text-3xl font-bold">{c.value}</div>
          </div>
        ))}
      </div>

      <div className="rounded-xl border bg-gradient-brand p-8 text-white shadow-elegant">
        <h2 className="text-2xl font-bold">Get started</h2>
        <p className="mt-2 text-white/90">
          Add your first patient, assign the doctor name, schedule a timed appointment, then manage
          queue check-in, EMR timeline, and follow-up reminders from role-based screens.
        </p>
      </div>

      <div className="rounded-xl border bg-card p-6 shadow-sm">
        <div>
          <h2 className="text-xl font-semibold">{roleDashboard.title}</h2>
          <p className="mt-1 text-sm text-muted-foreground">
            Widgets are customized for the current role and visible rights.
          </p>
        </div>
        <div className="mt-5 grid gap-3 md:grid-cols-3">
          {roleDashboard.widgets.map(([label, desc, Icon]) => (
            <div key={label} className="rounded-lg border bg-muted/30 p-4">
              <Icon className="h-5 w-5 text-brand-blue" />
              <div className="mt-3 font-medium">{label}</div>
              <p className="mt-1 text-xs text-muted-foreground">{desc}</p>
            </div>
          ))}
        </div>
      </div>

      <div className="rounded-xl border bg-card p-6 shadow-sm">
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div>
            <div className="flex items-center gap-2">
              <ShieldCheck className="h-5 w-5 text-brand-blue" />
              <h2 className="text-xl font-semibold">Role-wise access</h2>
            </div>
            <p className="mt-2 max-w-2xl text-sm text-muted-foreground">
              {access?.copy.focus ?? "Loading current role access..."}
            </p>
          </div>
          <Badge className="bg-gradient-brand text-white">{access?.copy.label ?? "Role"}</Badge>
        </div>
        <div className="mt-5 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
          {rights.map(([label, enabled, desc]) => (
            <div key={label} className="rounded-lg border bg-muted/30 p-4">
              <div className="flex items-center gap-2 text-sm font-medium">
                <CheckCircle2
                  className={enabled ? "h-4 w-4 text-primary" : "h-4 w-4 text-muted-foreground"}
                />
                {label}
              </div>
              <p className="mt-1 text-xs text-muted-foreground">{desc}</p>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
