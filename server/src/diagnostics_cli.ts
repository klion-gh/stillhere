/**
 * Operator CLI for the diagnostic trail. Runs inside the backend container,
 * talking straight to the database:
 *
 *     node dist/diagnostics_cli.js on|off|status|tail [n]|export|clear
 *
 * Deliberately not an HTTP endpoint. Anything served by the node is reachable
 * from the internet through Caddy, and a switch that turns on recording of
 * everyone's activity is not something to expose and then defend with a
 * password. The running server notices the change within a few seconds.
 */
import "dotenv/config";
import { prisma } from "./db/prisma.js";
import {
  loadDiagnosticsState,
  pruneOldEvents,
  RETENTION_DAYS,
  setDiagnosticsEnabled,
} from "./modules/diagnostics/store.js";

function usage(): never {
  console.log(`Использование: diagnostics.sh <команда>

  on            включить запись действий
  off           выключить запись
  status        показать состояние и число событий
  tail [N]      показать последние N событий (по умолчанию 50)
  export        выгрузить всё в JSON (в stdout)
  clear         удалить все записанные события

Записи хранятся ${RETENTION_DAYS} дня и удаляются автоматически.`);
  process.exit(1);
}

async function status() {
  const enabled = await loadDiagnosticsState();
  const total = await prisma.diagnosticEvent.count();
  const oldest = await prisma.diagnosticEvent.findFirst({ orderBy: { at: "asc" }, select: { at: true } });
  console.log(`Запись: ${enabled ? "ВКЛЮЧЕНА" : "выключена"}`);
  console.log(`Событий: ${total}`);
  if (oldest) console.log(`Самое старое: ${oldest.at.toISOString()}`);
  console.log(`Срок хранения: ${RETENTION_DAYS} дня`);
}

async function tail(limit: number) {
  const rows = await prisma.diagnosticEvent.findMany({
    orderBy: { at: "desc" },
    take: limit,
  });
  for (const row of rows.reverse()) {
    const who = row.username ?? row.userId ?? "-";
    const detail = row.detail ? ` ${row.detail}` : "";
    const data = row.data ? ` ${JSON.stringify(row.data)}` : "";
    console.log(`${row.at.toISOString()} [${row.source}] ${who} ${row.kind}${detail}${data}`);
  }
  if (rows.length === 0) console.log("(пусто)");
}

async function main() {
  const [command, arg] = process.argv.slice(2);

  switch (command) {
    case "on":
      await setDiagnosticsEnabled(true);
      console.log("Запись включена. Приложения начнут отправлять события в течение ~15 секунд.");
      break;
    case "off":
      await setDiagnosticsEnabled(false);
      console.log(`Запись выключена. Уже собранное удалится само через ${RETENTION_DAYS} дня.`);
      break;
    case "status":
      await status();
      break;
    case "tail":
      await tail(Number(arg) > 0 ? Number(arg) : 50);
      break;
    case "export": {
      const rows = await prisma.diagnosticEvent.findMany({ orderBy: { at: "asc" } });
      console.log(JSON.stringify(rows, null, 2));
      break;
    }
    case "clear": {
      const { count } = await prisma.diagnosticEvent.deleteMany({});
      console.log(`Удалено событий: ${count}`);
      break;
    }
    case "prune": {
      const count = await pruneOldEvents();
      console.log(`Удалено просроченных: ${count}`);
      break;
    }
    default:
      usage();
  }

  await prisma.$disconnect();
}

main().catch(async (err) => {
  console.error(err);
  await prisma.$disconnect();
  process.exit(1);
});
