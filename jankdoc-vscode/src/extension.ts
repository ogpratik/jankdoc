/**
 * JankDoc VS Code Companion Extension
 *
 * Lifecycle:
 *   1. Activates on any `dart` debug session start (Flutter run/debug).
 *   2. Discovers the `jankdoc_daemon` binary from the project's pub cache.
 *   3. Starts the daemon as a child process if not already running.
 *   4. Shows a status-bar item with connection state.
 *   5. Kills the daemon when the debug session ends (or VS Code closes).
 *
 * Zero code changes required in the Flutter app — this is the alternative
 * to calling `JankDoc.attach()` in main.dart.
 */

import * as vscode from 'vscode';
import * as http from 'http';
import * as path from 'path';
import * as fs from 'fs';
import { ChildProcess, spawn } from 'child_process';

// ── State ─────────────────────────────────────────────────────────────────────

let daemonProcess: ChildProcess | null = null;
let statusBarItem: vscode.StatusBarItem;
let outputChannel: vscode.OutputChannel;

// ── Activation ────────────────────────────────────────────────────────────────

export function activate(context: vscode.ExtensionContext): void {
  outputChannel = vscode.window.createOutputChannel('JankDoc');
  statusBarItem = vscode.window.createStatusBarItem(
    vscode.StatusBarAlignment.Right,
    100,
  );
  statusBarItem.command = 'jankdoc.openDevTools';
  statusBarItem.tooltip = 'JankDoc Analysis Daemon';
  updateStatusBar('idle');
  statusBarItem.show();

  // Commands
  context.subscriptions.push(
    vscode.commands.registerCommand('jankdoc.startDaemon', () =>
      startDaemon(),
    ),
    vscode.commands.registerCommand('jankdoc.stopDaemon', () => stopDaemon()),
    vscode.commands.registerCommand('jankdoc.openDevTools', () => {
      const cfg = getConfig();
      vscode.env.openExternal(
        vscode.Uri.parse(`http://127.0.0.1:${cfg.port}`),
      );
    }),
  );

  // Auto-start on Flutter debug session
  context.subscriptions.push(
    vscode.debug.onDidStartDebugSession((session) => {
      if (session.type === 'dart' && getConfig().autoStart) {
        outputChannel.appendLine(
          `[JankDoc] Flutter debug session started: ${session.name}`,
        );
        startDaemon();
      }
    }),
    vscode.debug.onDidTerminateDebugSession((session) => {
      if (session.type === 'dart') {
        outputChannel.appendLine(
          `[JankDoc] Flutter debug session ended: ${session.name}`,
        );
        stopDaemon();
      }
    }),
  );

  context.subscriptions.push(statusBarItem, outputChannel);
}

export function deactivate(): void {
  stopDaemon();
}

// ── Daemon lifecycle ──────────────────────────────────────────────────────────

async function startDaemon(): Promise<void> {
  const cfg = getConfig();

  // Check if already running
  if (await isHealthy(cfg.port)) {
    outputChannel.appendLine(
      `[JankDoc] Daemon already running on port ${cfg.port}`,
    );
    updateStatusBar('connected');
    return;
  }

  const binary = findDaemonBinary();
  if (!binary) {
    const msg =
      'JankDoc daemon binary not found. Add `await JankDoc.attach()` to ' +
      'main() (it downloads the daemon) or run `dart run jankdoc:daemon`.';
    outputChannel.appendLine(`[JankDoc] ${msg}`);
    vscode.window.showWarningMessage(`JankDoc: ${msg}`);
    updateStatusBar('error');
    return;
  }

  outputChannel.appendLine(
    `[JankDoc] Starting daemon: ${binary} --port ${cfg.port}`,
  );
  updateStatusBar('connecting');

  daemonProcess = spawn(
    binary,
    [
      '--port', String(cfg.port),
      '--ollama-url', cfg.ollamaUrl,
      '--model', cfg.model,
    ],
    { detached: false, stdio: ['ignore', 'pipe', 'pipe'] },
  );

  daemonProcess.stdout?.on('data', (data: Buffer) => {
    outputChannel.append(data.toString());
  });
  daemonProcess.stderr?.on('data', (data: Buffer) => {
    outputChannel.append(data.toString());
  });
  daemonProcess.on('exit', (code) => {
    outputChannel.appendLine(`[JankDoc] Daemon exited with code ${code}`);
    daemonProcess = null;
    updateStatusBar('idle');
  });

  // Wait up to 10s for /health to respond
  const ready = await waitForHealth(cfg.port, 10_000);
  if (ready) {
    outputChannel.appendLine(
      `[JankDoc] Daemon ready on http://127.0.0.1:${cfg.port}`,
    );
    updateStatusBar('connected');
  } else {
    outputChannel.appendLine('[JankDoc] Daemon did not become healthy in 10s');
    updateStatusBar('error');
  }
}

function stopDaemon(): void {
  if (daemonProcess) {
    outputChannel.appendLine('[JankDoc] Stopping daemon…');
    daemonProcess.kill('SIGINT');
    daemonProcess = null;
  }
  updateStatusBar('idle');
}

// ── Status bar ────────────────────────────────────────────────────────────────

type StatusKind = 'idle' | 'connecting' | 'connected' | 'error';

function updateStatusBar(status: StatusKind): void {
  const [icon, text] = statusMap[status];
  statusBarItem.text = `${icon} JankDoc${text ? `: ${text}` : ''}`;
  statusBarItem.backgroundColor =
    status === 'error'
      ? new vscode.ThemeColor('statusBarItem.errorBackground')
      : undefined;
  statusBarItem.color =
    status === 'connected'
      ? new vscode.ThemeColor('statusBarItem.prominentForeground')
      : undefined;
}

const statusMap: Record<StatusKind, [string, string]> = {
  idle:       ['$(pulse)', ''],
  connecting: ['$(sync~spin)', 'connecting'],
  connected:  ['$(check)', 'connected'],
  error:      ['$(error)', 'error'],
};

// ── Helpers ───────────────────────────────────────────────────────────────────

interface JankDocConfig {
  port: number;
  ollamaUrl: string;
  model: string;
  autoStart: boolean;
}

function getConfig(): JankDocConfig {
  const cfg = vscode.workspace.getConfiguration('jankdoc');
  return {
    port: cfg.get<number>('port', 9101),
    ollamaUrl: cfg.get<string>('ollamaUrl', 'http://127.0.0.1:11434'),
    model: cfg.get<string>('model', 'qwen2.5-coder:7b'),
    autoStart: cfg.get<boolean>('autoStart', true),
  };
}

/**
 * Searches for the pre-compiled `jankdoc_daemon` binary.
 *
 * Search order:
 *   1. `<workspace>/packages/jankdoc/bin/jankdoc_daemon`  (monorepo dev)
 *   2. `~/.pub-cache/bin/jankdoc_daemon`                  (pub global activate)
 *   3. `jankdoc_daemon` on PATH
 */
function findDaemonBinary(): string | null {
  const candidates: string[] = [];

  // Monorepo layout
  const workspaceFolders = vscode.workspace.workspaceFolders ?? [];
  for (const folder of workspaceFolders) {
    candidates.push(
      path.join(folder.uri.fsPath, 'packages', 'jankdoc', 'bin', 'jankdoc_daemon'),
    );
  }

  // pub-cache global
  const home = process.env['HOME'] ?? process.env['USERPROFILE'] ?? '';
  candidates.push(path.join(home, '.pub-cache', 'bin', 'jankdoc_daemon'));

  // Windows variants
  candidates.push(path.join(home, 'AppData', 'Local', 'Pub', 'Cache', 'bin', 'jankdoc_daemon.exe'));

  for (const candidate of candidates) {
    if (fs.existsSync(candidate)) {
      return candidate;
    }
  }

  // Fallback: rely on PATH
  return 'jankdoc_daemon';
}

function isHealthy(port: number): Promise<boolean> {
  return new Promise((resolve) => {
    const req = http.get(
      `http://127.0.0.1:${port}/health`,
      { timeout: 2000 },
      (res) => resolve(res.statusCode === 200),
    );
    req.on('error', () => resolve(false));
    req.on('timeout', () => { req.destroy(); resolve(false); });
  });
}

async function waitForHealth(port: number, timeoutMs: number): Promise<boolean> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (await isHealthy(port)) return true;
    await sleep(300);
  }
  return false;
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// Workaround for unused variable linting without disabling the rule globally
declare const _: unknown;
