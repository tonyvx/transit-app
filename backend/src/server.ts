import { createApp } from "./app.ts";
import { MbtaProvider } from "./providers/mbta/MbtaProvider.ts";
import { SqliteStore } from "./store/store.ts";

const key = process.env.MBTA_API_KEY;
if (!key) throw new Error("MBTA_API_KEY is not set (see ../.env)");

const store = new SqliteStore(process.env.DB_PATH ?? "transit.sqlite");
setInterval(() => store.prune(Date.now() - 10 * 60_000), 60_000).unref();

const port = Number(process.env.PORT ?? 3000);
createApp(new MbtaProvider(key), store).listen(port, () => console.log(`listening on :${port}`));
