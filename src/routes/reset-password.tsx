import { createFileRoute, Link, useNavigate } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import { Check, KeyRound, X } from "lucide-react";
import { toast } from "sonner";
import { supabase } from "@/integrations/supabase/client";
import { passwordError, passwordRequirements } from "@/lib/password-security";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";

export const Route = createFileRoute("/reset-password")({
  component: ResetPasswordPage,
});

function ResetPasswordPage() {
  const navigate = useNavigate();
  const [password, setPassword] = useState("");
  const [confirmation, setConfirmation] = useState("");
  const [checking, setChecking] = useState(true);
  const [validRecovery, setValidRecovery] = useState(false);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    let active = true;
    const searchParams = new URLSearchParams(window.location.search);
    const recoveryCode = searchParams.get("code");
    const recoveryInUrl =
      window.location.hash.includes("type=recovery") ||
      searchParams.get("type") === "recovery" ||
      !!recoveryCode;

    const { data: listener } = supabase.auth.onAuthStateChange((event, session) => {
      if (!active) return;
      if (event === "PASSWORD_RECOVERY") {
        setValidRecovery(!!session);
        setChecking(false);
      }
    });

    if (!recoveryInUrl) {
      setChecking(false);
    } else {
      const verifyRecovery = async () => {
        if (recoveryCode) {
          const { error } = await supabase.auth.exchangeCodeForSession(recoveryCode);
          if (error) return false;
        }

        const { data } = await supabase.auth.getSession();
        return !!data.session;
      };

      const timeout = new Promise<boolean>((resolve) => {
        window.setTimeout(() => resolve(false), 5000);
      });

      void Promise.race([verifyRecovery(), timeout])
        .then((valid) => {
          if (active) setValidRecovery(valid);
        })
        .finally(() => {
          if (active) setChecking(false);
        });
    }

    return () => {
      active = false;
      listener.subscription.unsubscribe();
    };
  }, []);

  const updatePassword = async () => {
    const requirementError = passwordError(password);
    if (requirementError) {
      toast.error(requirementError);
      return;
    }
    if (password !== confirmation) {
      toast.error("Passwords do not match");
      return;
    }

    setSaving(true);
    const { error } = await supabase.auth.updateUser({ password });
    if (!error) await supabase.auth.signOut({ scope: "local" });
    setSaving(false);

    if (error) {
      toast.error(error.message);
      return;
    }

    window.history.replaceState({}, document.title, "/reset-password");
    toast.success("Password updated. Sign in with your new password.");
    navigate({ to: "/login", replace: true });
  };

  return (
    <main className="min-h-screen bg-background px-4 py-12 text-foreground">
      <section className="mx-auto max-w-md rounded-lg border bg-card p-6">
        <KeyRound className="h-9 w-9 text-primary" />
        <h1 className="mt-3 text-2xl font-semibold">Choose a new password</h1>

        {checking ? (
          <p className="mt-5 text-sm text-muted-foreground">Checking recovery link...</p>
        ) : !validRecovery ? (
          <div className="mt-5 space-y-4">
            <p className="rounded-md border border-destructive/30 bg-destructive/10 p-3 text-sm">
              This recovery link is invalid, expired, or has already been used.
            </p>
            <Button asChild className="w-full">
              <Link to="/forgot-password">Request another link</Link>
            </Button>
          </div>
        ) : (
          <form
            className="mt-6 space-y-4"
            onSubmit={(event) => {
              event.preventDefault();
              void updatePassword();
            }}
          >
            <div>
              <Label htmlFor="new-password">New password</Label>
              <Input
                id="new-password"
                type="password"
                autoComplete="new-password"
                value={password}
                onChange={(event) => setPassword(event.target.value)}
              />
            </div>
            <div>
              <Label htmlFor="confirm-password">Confirm password</Label>
              <Input
                id="confirm-password"
                type="password"
                autoComplete="new-password"
                value={confirmation}
                onChange={(event) => setConfirmation(event.target.value)}
              />
            </div>
            <div className="space-y-1 rounded-md border p-3 text-xs">
              {passwordRequirements.map((requirement) => {
                const valid = requirement.test(password);
                return (
                  <div key={requirement.label} className="flex items-center gap-2">
                    {valid ? (
                      <Check className="h-3.5 w-3.5 text-emerald-600" />
                    ) : (
                      <X className="h-3.5 w-3.5 text-muted-foreground" />
                    )}
                    {requirement.label}
                  </div>
                );
              })}
            </div>
            <Button type="submit" className="w-full" disabled={saving}>
              {saving ? "Updating..." : "Update password"}
            </Button>
          </form>
        )}
      </section>
    </main>
  );
}
