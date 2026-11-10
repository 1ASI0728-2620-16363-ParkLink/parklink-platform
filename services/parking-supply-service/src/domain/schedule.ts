export interface Window { start: string; end: string }
export function validWindows(windows: Window[]) {
  const sorted = [...windows].sort((a,b) => Date.parse(a.start)-Date.parse(b.start));
  return sorted.every((w,i) => Date.parse(w.start)<Date.parse(w.end) && (!i || Date.parse(sorted[i-1]!.end)<=Date.parse(w.start)));
}
