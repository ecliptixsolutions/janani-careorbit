/* eslint-disable @typescript-eslint/no-explicit-any */
import { Link, useLocation, useNavigate } from "@tanstack/react-router";
import {
  Activity,
  BotMessageSquare,
  CalendarDays,
  ClipboardList,
  DatabaseBackup,
  FileText,
  FlaskConical,
  History,
  Import,
  LayoutDashboard,
  LayoutGrid,
  ListOrdered,
  LogOut,
  Pill,
  ReceiptIndianRupee,
  Settings,
  ShieldCheck,
  MonitorCheck,
  Users,
} from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { cn } from "@/lib/utils";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { toast } from "sonner";
import { useRoleAccess } from "@/hooks/use-role-access";
import { useAuth } from "@/hooks/use-auth";
import { getSessionId } from "@/hooks/use-session-tracking";
import { NotificationBell } from "@/components/notification-bell";

const items = [
  { to: "/dashboard", label: "Overview", icon: LayoutDashboard, permission: "canViewDashboard" },
  { to: "/patients", label: "Patients", icon: Users, permission: "canViewPatients" },
  {
    to: "/patient-history",
    label: "History",
    icon: History,
    permission: "canViewPatientHistory",
  },
  {
    to: "/appointments",
    label: "Appointments",
    icon: CalendarDays,
    permission: "canViewAppointments",
  },
  { to: "/queue", label: "Queue", icon: ListOrdered, permission: "canViewQueue" },
  {
    to: "/emr-timeline",
    label: "EMR Timeline",
    icon: ClipboardList,
    permission: "canViewEmrTimeline",
  },
  {
    to: "/prescriptions",
    label: "Prescriptions",
    icon: FileText,
    permission: "canViewPrescriptions",
  },
  { to: "/lab", label: "Laboratory", icon: FlaskConical, permission: "canAccessLab" },
  { to: "/pharmacy", label: "Pharmacy", icon: Pill, permission: "canAccessPharmacy" },
  {
    to: "/billing",
    label: "Billing",
    icon: ReceiptIndianRupee,
    permission: "canAccessBilling",
  },
  {
    to: "/automations",
    label: "Automations",
    icon: BotMessageSquare,
    permission: "canManageAutomations",
  },
  { to: "/modules", label: "Modules", icon: LayoutGrid, permission: "canViewModules" },
  { to: "/sessions", label: "Security", icon: MonitorCheck, permission: "canViewModules" },
  {
    to: "/imports",
    label: "Data Imports",
    icon: Import,
    permission: "canManageImports",
  },
  {
    to: "/organization-settings",
    label: "Hospital Settings",
    icon: Settings,
    permission: "canManageUsers",
  },
  {
    to: "/access-control",
    label: "Access Control",
    icon: ShieldCheck,
    permission: "canManageUsers",
  },
  {
    to: "/system-admin",
    label: "Audit & Backup",
    icon: DatabaseBackup,
    permission: "canManageUsers",
  },
] as const;

export function AppShell({ children }: { children: React.ReactNode }) {
  const location = useLocation();
  const navigate = useNavigate();
  const { data: access } = useRoleAccess();
  const { session, user } = useAuth();
  const visibleItems = items.filter((item) => access?.permissions[item.permission] ?? true);

  const signOut = async () => {
    const sessionId = getSessionId(session);
    if (sessionId && user) {
      await (supabase as any)
        .from("user_sessions")
        .update({ revoked_at: new Date().toISOString(), revoked_reason: "user_logout" })
        .eq("id", sessionId)
        .eq("user_id", user.id);
    }
    await supabase.auth.signOut();
    toast.success("Signed out");
    navigate({ to: "/" });
  };

  return (
    <div className="flex min-h-screen bg-muted/30">
      <aside className="hidden w-64 flex-col border-r bg-sidebar md:flex">
        <Link to="/" className="flex h-16 items-center gap-2 border-b px-6">
          <div className="flex h-8 w-8 items-center justify-center rounded-md bg-gradient-brand">
            <Activity className="h-4 w-4 text-white" />
          </div>
          <span className="font-bold">
            Care<span className="text-gradient-brand">Orbit</span>
          </span>
        </Link>
        <nav className="flex-1 space-y-1 p-3">
          {visibleItems.map((it) => {
            const active = location.pathname === it.to;
            return (
              <Link
                key={it.to}
                to={it.to}
                className={cn(
                  "flex items-center gap-3 rounded-md px-3 py-2 text-sm font-medium transition-colors",
                  active
                    ? "bg-gradient-brand text-white shadow-glow"
                    : "text-sidebar-foreground hover:bg-sidebar-accent",
                )}
              >
                <it.icon className="h-4 w-4" />
                {it.label}
              </Link>
            );
          })}
        </nav>
        <div className="border-t p-3">
          <div className="mb-3 flex items-center justify-between rounded-lg border bg-sidebar-accent/60 p-2">
            <span className="px-1 text-xs font-medium text-sidebar-foreground">Alerts</span>
            <NotificationBell />
          </div>
          <div className="mb-3 rounded-lg border bg-sidebar-accent/60 p-3 text-xs text-sidebar-foreground">
            <div className="mb-2 flex items-center gap-2">
              <ShieldCheck className="h-3.5 w-3.5 text-brand-blue" />
              <Badge variant="secondary" className="bg-background/70 text-foreground">
                {access?.copy.label ?? "Role"}
              </Badge>
            </div>
            <p className="leading-relaxed text-sidebar-foreground/80">
              {access?.copy.description ?? "Loading access rights..."}
            </p>
          </div>
          <Button onClick={signOut} variant="ghost" className="w-full justify-start">
            <LogOut className="mr-2 h-4 w-4" /> Sign out
          </Button>
        </div>
      </aside>
      <main className="flex-1 overflow-x-hidden">
        <div className="md:hidden flex h-14 items-center justify-between border-b bg-background px-4">
          <Link to="/dashboard" className="flex items-center gap-2 font-bold">
            <Activity className="h-5 w-5 text-primary" /> CareOrbit
          </Link>
          <div className="flex items-center gap-2">
            <NotificationBell />
            <Badge variant="secondary" className="max-w-28 truncate">
              {access?.copy.label ?? "Role"}
            </Badge>
            <Button onClick={signOut} variant="ghost" size="sm">
              <LogOut className="h-4 w-4" />
            </Button>
          </div>
        </div>
        <nav className="md:hidden flex gap-1 overflow-x-auto border-b bg-background p-2">
          {visibleItems.map((it) => {
            const active = location.pathname === it.to;
            return (
              <Link
                key={it.to}
                to={it.to}
                className={cn(
                  "flex items-center gap-2 whitespace-nowrap rounded-md px-3 py-1.5 text-sm",
                  active ? "bg-primary text-primary-foreground" : "text-muted-foreground",
                )}
              >
                <it.icon className="h-4 w-4" />
                {it.label}
              </Link>
            );
          })}
        </nav>
        <div className="p-6 md:p-8">{children}</div>
      </main>
    </div>
  );
}
