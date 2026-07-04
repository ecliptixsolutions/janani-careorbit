import { createFileRoute, Link } from "@tanstack/react-router";
import { useState } from "react";
import { ArrowLeft, Mail } from "lucide-react";
import { toast } from "sonner";
import { supabase } from "@/integrations/supabase/client";
import { isValidEmail } from "@/lib/password-security";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";

export const Route = createFileRoute("/forgot-password")({
  component: ForgotPasswordPage,
});

const genericMessage =
  "If an account exists for that email, a secure password-reset link has been sent.";

function ForgotPasswordPage() {
  const [email, setEmail] = useState("");
  const [loading, setLoading] = useState(false);
  const [submitted, setSubmitted] = useState(false);

  const submit = async () => {
    if (!isValidEmail(email)) {
      toast.error("Enter a valid email address");
      return;
    }

    setLoading(true);
    const redirectTo = new URL("/reset-password", window.location.origin).toString();
    const { error } = await supabase.auth.resetPasswordForEmail(email.trim().toLowerCase(), {
      redirectTo,
    });
    setLoading(false);

    if (error && /rate|limit/i.test(error.message)) {
      toast.error("Too many reset attempts. Please wait before trying again.");
      return;
    }

    setSubmitted(true);
    toast.success(genericMessage);
  };

  return (
    <main className="min-h-screen bg-background px-4 py-12 text-foreground">
      <section className="mx-auto max-w-md rounded-lg border bg-card p-6">
        <Link to="/login" className="inline-flex items-center text-sm text-primary">
          <ArrowLeft className="mr-1 h-4 w-4" /> Back to sign in
        </Link>
        <Mail className="mt-6 h-9 w-9 text-primary" />
        <h1 className="mt-3 text-2xl font-semibold">Reset your password</h1>
        <p className="mt-1 text-sm text-muted-foreground">
          Enter the email address used for your CareOrbit account.
        </p>

        {submitted ? (
          <div className="mt-6 rounded-md border bg-muted/30 p-4 text-sm">{genericMessage}</div>
        ) : (
          <form
            className="mt-6 space-y-4"
            onSubmit={(event) => {
              event.preventDefault();
              void submit();
            }}
          >
            <div>
              <Label htmlFor="reset-email">Email</Label>
              <Input
                id="reset-email"
                type="email"
                autoComplete="email"
                value={email}
                onChange={(event) => setEmail(event.target.value)}
              />
            </div>
            <Button type="submit" className="w-full" disabled={loading}>
              {loading ? "Sending..." : "Send reset link"}
            </Button>
          </form>
        )}
      </section>
    </main>
  );
}
