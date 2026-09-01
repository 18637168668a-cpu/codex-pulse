import { createInstaller } from './installer.mjs';
try {
  const installer = createInstaller();
  const [action, ...args] = process.argv.slice(2);
  if (action === 'preflight' && !args.length) await installer.preflight();
  else if (action === 'install' && !args.length) await installer.install();
  else if (action === 'install-prebuilt' && args.length === 2 && args[0] === '--app') await installer.install(args[1]);
  else if (action === 'social' && args.length === 1) installer.social(args[0]);
  else if (action === 'uninstall' && !args.length) installer.uninstall(true);
  else if (action === 'remove-bridge' && !args.length) installer.uninstall(false);
  else throw new Error('Expected preflight, install, install-prebuilt --app <path>, social on|off, remove-bridge or uninstall.');
} catch (error) { console.error(error.message); process.exitCode = 1; }
