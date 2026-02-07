import { useMutation } from "@tanstack/react-query";
import { useRouter } from "@tanstack/react-router";
import toast from "react-hot-toast";
import { Button } from "~/components/shared/button";
import { Input } from "~/components/shared/input";
import { useProfile } from "~/hooks/use-profile";
import { useResult } from "~/hooks/use-result";
import { useSchedule } from "~/hooks/use-schedule";
import { useToken } from "~/hooks/use-token";

const LoginForm = () => {
	const { reset: ProfileReset } = useProfile();
	const { reset: ScheduleReset } = useSchedule();
	const { reset: ResultReset } = useResult();
	const { setToken } = useToken();

	const router = useRouter();

	// Supabase Configuration (Hardcoded for client-side fetching)
	const SUPABASE_URL = "https://vcwdryhfqriswkmpqzlv.supabase.co";
	const SUPABASE_ANON = "sb_publishable_M1z7AX7175IJGQLt3TxMVw_5W-37CXy";

	const getScraperUrl = async () => {
		try {
			// Try local first for dev
			const localCheck = await fetch("http://localhost:3001/").catch(() => null);
			if (localCheck?.ok) return "http://localhost:3001";

			// Fetch from Supabase
			const res = await fetch(
				`${SUPABASE_URL}/rest/v1/bot_settings?key=eq.imaluum_scraper_url&select=value`,
				{
					headers: {
						apikey: SUPABASE_ANON,
						Authorization: `Bearer ${SUPABASE_ANON}`,
					},
				},
			);
			const data = await res.json();
			if (data && data[0] && data[0].value && data[0].value.url) {
				return data[0].value.url;
			}
			throw new Error("Could not retrieve Scraper URL");
		} catch (e) {
			console.error("Failed to get API URL", e);
			return null;
		}
	};

	const loginMutation = useMutation({
		mutationKey: ["login"],
		mutationFn: async ({
			username,
			password,
		}: { username: string; password: string }) => {

			const API_URL = await getScraperUrl();
			if (!API_URL) throw new Error("Scraper is offline");

			const res = await fetch(`${API_URL}/api/login`, {
				credentials: "include",
				method: "POST",
				headers: {
					"Content-Type": "application/json",
					"X-Pinggy-No-Screen": "true", // Bypass Pinggy warning
				},
				body: JSON.stringify({ username, password }),
			});

			const json = await res.json();

			if (!res.ok) {
				console.error("Error: ", json.message);
				toast.error("An error occurred. Please try again later.");
				return Promise.reject(json.message);
			}

			return json.data;
		},
		onSuccess: (data) => {
			ProfileReset();
			ScheduleReset();
			ResultReset();

			setToken(data.token);

			router.navigate({
				to: "/dashboard",
			});
		},
		onError: (err) => {
			console.error("Error: ", err);
			toast.error("An error occurred. Please try again later.");
		},
	});

	const handleLogin = async (e: React.FormEvent<HTMLFormElement>) => {
		e.preventDefault();
		const form = new FormData(e.currentTarget);

		const username = form.get("username") as string;
		const password = form.get("password") as string;

		await loginMutation.mutateAsync({ username, password });
	};

	return (
		<form onSubmit={handleLogin} className="mt-10 w-fit space-y-2">
			<div className="flex items-center justify-center gap-3">
				<Input
					name="username"
					placeholder="Matric Number"
					disabled={loginMutation.isPending}
				/>
				<Input
					name="password"
					placeholder="Password"
					type="password"
					disabled={loginMutation.isPending}
				/>
			</div>
			<Button
				type="submit"
				disabled={loginMutation.isPending}
				className="float-right"
			>
				<span className="text-foreground">
					{loginMutation.isPending ? "Logging in" : "Log in"}
				</span>
			</Button>
		</form>
	);
};

export default LoginForm;
