import { createFileRoute, Link, useNavigate } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import { toast } from "sonner";
import { supabase } from "@/integrations/supabase/client";

export const Route = createFileRoute("/login")({
  component: LoginPage,
});

function LoginPage() {
  const navigate = useNavigate();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [loading, setLoading] = useState(false);
  const [errorMessage, setErrorMessage] = useState("");

  useEffect(() => {
    let active = true;

    supabase.auth.getSession().then(({ data: { session } }) => {
      if (active && session) navigate({ to: "/dashboard" });
    });

    return () => {
      active = false;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const handleSubmit = async () => {
    const trimmedEmail = email.trim();

    if (!trimmedEmail || !password) {
      setErrorMessage("Please enter your email and password");
      toast.error("Please enter your email and password");
      return;
    }

    setLoading(true);
    setErrorMessage("");
    const { error } = await supabase.auth.signInWithPassword({ email: trimmedEmail, password });
    setLoading(false);

    if (error) {
      setErrorMessage(error.message);
      toast.error(error.message);
      return;
    }

    toast.success("Welcome back!");
    navigate({ to: "/dashboard" });
  };

  return (
    <div className="min-h-screen bg-background px-4 py-10 text-foreground">
      <div className="mx-auto max-w-md rounded-xl border border-border bg-card p-6">
        <Link to="/" className="mb-4 inline-block text-sm text-primary">
          CareOrbit
        </Link>
        <h1 className="text-2xl font-semibold">Welcome back</h1>
        <p className="mt-1 text-sm text-muted-foreground">Sign in to your CareOrbit account</p>

        <form
          className="mt-6 space-y-4"
          autoComplete="on"
          onSubmit={(event) => {
            event.preventDefault();
            void handleSubmit();
          }}
        >
          <div>
            <label htmlFor="email" className="mb-1 block text-sm font-medium">
              Email
            </label>
            <input
              id="email"
              name="email"
              value={email}
              onChange={(event) => setEmail(event.target.value)}
              type="email"
              autoComplete="email"
              autoCapitalize="none"
              autoCorrect="off"
              className="h-10 w-full rounded-md border border-border bg-background px-3 text-sm outline-none"
            />
          </div>

          <div>
            <div className="mb-1 flex items-center justify-between gap-3">
              <label htmlFor="password" className="block text-sm font-medium">
                Password
              </label>
              <Link to="/forgot-password" className="text-xs text-primary hover:underline">
                Forgot password?
              </Link>
            </div>
            <input
              id="password"
              name="password"
              value={password}
              onChange={(event) => setPassword(event.target.value)}
              type="password"
              autoComplete="current-password"
              autoCapitalize="none"
              autoCorrect="off"
              spellCheck={false}
              className="h-10 w-full rounded-md border border-border bg-background px-3 text-sm outline-none"
            />
          </div>

          {errorMessage && (
            <div className="rounded-md border border-destructive/30 bg-destructive/10 px-3 py-2 text-sm text-destructive">
              {errorMessage}
            </div>
          )}

          <button
            type="submit"
            disabled={loading}
            className="h-10 w-full rounded-md bg-primary text-sm font-medium text-primary-foreground"
          >
            {loading ? "Signing in..." : "Sign in"}
          </button>
        </form>

        <p className="mt-6 text-sm text-muted-foreground">
          New here?{" "}
          <Link to="/signup" className="text-primary underline-offset-4 hover:underline">
            Create an account
          </Link>
        </p>
      </div>
    </div>
  );
}
