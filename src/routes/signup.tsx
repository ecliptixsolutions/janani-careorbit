import { createFileRoute, Link, useNavigate } from "@tanstack/react-router";
import { useState } from "react";
import { toast } from "sonner";
import { Activity, CheckCircle2, Circle, Eye, EyeOff, KeyRound } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { databaseRoleFor, signupRoleOptions, type RoleKey } from "@/lib/access-control";

export const Route = createFileRoute("/signup")({
  component: SignupPage,
});

const passwordRules = [
  { label: "At least 8 characters", test: (value: string) => value.length >= 8 },
  { label: "One uppercase letter", test: (value: string) => /[A-Z]/.test(value) },
  { label: "One lowercase letter", test: (value: string) => /[a-z]/.test(value) },
  { label: "One number", test: (value: string) => /\d/.test(value) },
  { label: "One special character", test: (value: string) => /[^A-Za-z0-9]/.test(value) },
];

const passwordCharacters = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#$%^&*?";

function getPasswordChecks(password: string) {
  return passwordRules.map((rule) => ({ ...rule, passed: rule.test(password) }));
}

function getRandomIndex(length: number) {
  const values = new Uint32Array(1);
  crypto.getRandomValues(values);
  return values[0] % length;
}

function generateStrongPassword() {
  const requiredCharacters = ["A", "z", "7", "!"];
  const remainingCharacters = Array.from({ length: 10 }, () => {
    return passwordCharacters[getRandomIndex(passwordCharacters.length)];
  });

  return [...requiredCharacters, ...remainingCharacters]
    .map((character) => ({ character, sort: getRandomIndex(1000) }))
    .sort((a, b) => a.sort - b.sort)
    .map(({ character }) => character)
    .join("");
}

function SignupPage() {
  const navigate = useNavigate();
  const [fullName, setFullName] = useState("");
  const [organization, setOrganization] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [showPassword, setShowPassword] = useState(false);
  const [role, setRole] = useState<RoleKey>("staff");
  const [loading, setLoading] = useState(false);
  const [errorMessage, setErrorMessage] = useState("");
  const passwordChecks = getPasswordChecks(password);
  const isPasswordStrong = passwordChecks.every((rule) => rule.passed);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!isPasswordStrong) {
      setErrorMessage("Password does not meet all strength requirements");
      toast.error("Password does not meet all strength requirements");
      return;
    }

    setLoading(true);
    setErrorMessage("");
    const requestedRole = databaseRoleFor(role);
    const { data, error } = await supabase.auth.signUp({
      email,
      password,
      options: {
        data: {
          full_name: fullName,
          organization,
          role: requestedRole.role,
          requested_role: role,
          custom_role_label: requestedRole.custom_label,
        },
      },
    });
    setLoading(false);

    if (error) {
      setErrorMessage(error.message);
      return toast.error(error.message);
    }

    if (!data.session) {
      const { error: signInError } = await supabase.auth.signInWithPassword({ email, password });
      if (signInError) {
        setErrorMessage("Account created. Please sign in with the same email and password.");
        toast.success("Account created. Please sign in.");
        navigate({ to: "/login" });
        return;
      }
    }

    toast.success("Account created");
    navigate({ to: "/dashboard" });
  };

  const handleSuggestPassword = () => {
    setPassword(generateStrongPassword());
    setShowPassword(true);
  };

  return (
    <div className="flex min-h-screen items-center justify-center bg-gradient-hero px-4 py-10">
      <div className="w-full max-w-md rounded-2xl border bg-card p-8 shadow-elegant">
        <Link to="/" className="mb-6 flex items-center justify-center gap-2">
          <div className="flex h-9 w-9 items-center justify-center rounded-lg bg-gradient-brand">
            <Activity className="h-5 w-5 text-white" />
          </div>
          <span className="text-xl font-bold">
            Care<span className="text-gradient-brand">Orbit</span>
          </span>
        </Link>
        <h1 className="text-center text-2xl font-bold">Create your account</h1>
        <p className="mt-1 text-center text-sm text-muted-foreground">
          Start managing your facility today
        </p>

        <form onSubmit={handleSubmit} className="mt-6 space-y-4">
          <div>
            <Label htmlFor="name">Full name</Label>
            <Input
              id="name"
              required
              value={fullName}
              onChange={(e) => {
                setFullName(e.target.value);
                setErrorMessage("");
              }}
            />
          </div>
          <div>
            <Label htmlFor="org">Organization</Label>
            <Input
              id="org"
              value={organization}
              onChange={(e) => {
                setOrganization(e.target.value);
                setErrorMessage("");
              }}
              placeholder="Clinic / Hospital name"
            />
          </div>
          <div>
            <Label>Your role</Label>
            <Select
              value={role}
              onValueChange={(v) => {
                setRole(v as RoleKey);
                setErrorMessage("");
              }}
            >
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {signupRoleOptions.map((option) => (
                  <SelectItem key={option.value} value={option.value}>
                    {option.label}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
            <p className="mt-2 text-xs text-muted-foreground">
              For testing, accounts are approved immediately with the selected role rights.
            </p>
          </div>
          <div>
            <Label htmlFor="email">Email</Label>
            <Input
              id="email"
              type="email"
              required
              value={email}
              onChange={(e) => {
                setEmail(e.target.value);
                setErrorMessage("");
              }}
            />
          </div>
          <div>
            <div className="mb-1 flex items-center justify-between gap-3">
              <Label htmlFor="password">Password</Label>
              <Button
                type="button"
                variant="ghost"
                size="sm"
                className="h-7 px-2 text-xs"
                onClick={handleSuggestPassword}
              >
                <KeyRound className="mr-1.5 h-3.5 w-3.5" />
                Suggest
              </Button>
            </div>
            <div className="relative">
              <Input
                id="password"
                type={showPassword ? "text" : "password"}
                required
                minLength={8}
                value={password}
                onChange={(e) => {
                  setPassword(e.target.value);
                  setErrorMessage("");
                }}
                className="pr-11"
              />
              <Button
                type="button"
                variant="ghost"
                size="icon"
                className="absolute right-1 top-1 h-8 w-8 text-muted-foreground hover:text-foreground"
                onClick={() => setShowPassword((value) => !value)}
                aria-label={showPassword ? "Hide password" : "Show password"}
                title={showPassword ? "Hide password" : "Show password"}
              >
                {showPassword ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
              </Button>
            </div>
            <div className="mt-3 rounded-lg border bg-muted/30 p-3 text-xs">
              <div className="mb-2 font-medium text-foreground">Password requirements</div>
              <div className="grid gap-1.5">
                {passwordChecks.map((rule) => (
                  <div
                    key={rule.label}
                    className={
                      rule.passed
                        ? "flex items-center gap-2 text-primary"
                        : "flex items-center gap-2 text-muted-foreground"
                    }
                  >
                    {rule.passed ? (
                      <CheckCircle2 className="h-3.5 w-3.5" />
                    ) : (
                      <Circle className="h-3.5 w-3.5" />
                    )}
                    <span>{rule.label}</span>
                  </div>
                ))}
              </div>
            </div>
          </div>
          {errorMessage && (
            <div className="rounded-lg border border-destructive/30 bg-destructive/10 px-3 py-2 text-sm text-destructive">
              {errorMessage}
            </div>
          )}
          <Button
            type="submit"
            disabled={loading}
            className="w-full bg-gradient-brand text-white hover:opacity-90"
          >
            {loading ? "Creating..." : "Create account"}
          </Button>
        </form>

        <p className="mt-6 text-center text-sm text-muted-foreground">
          Already have an account?{" "}
          <Link to="/login" className="font-medium text-primary hover:underline">
            Sign in
          </Link>
        </p>
      </div>
    </div>
  );
}
