import { formatCurrency } from "utils/currency";

export const CHART_COLORS = [
  "#4ae087", "#2dd4bf", "#34d399", "#6ee7b7",
  "#a7f3d0", "#86efac", "#4ade80", "#22c55e",
];

export const chartBase = {
  toolbar: { show: false },
  zoom: { enabled: false },
  foreColor: "#f5f5f5",
};

export const gridTheme = { borderColor: "#2f2f2f" };

export function xaxisLabels() {
  return { rotate: -45, rotateAlways: true, style: { colors: "#f5f5f5" } };
}

export function yaxisLabels() {
  return { style: { colors: "#f5f5f5" }, formatter: (v) => formatCurrency(v) };
}

export function legendTheme() {
  return { position: "top", horizontalAlign: "left", labels: { colors: "#f5f5f5" } };
}

// Show a tick every 5 years for long projections, every 2 for medium,
// every 1 for short spans (under 15 years).
export function xAxisTickAmount(count) {
  if (count > 20) return Math.floor(count / 5);
  if (count > 15) return Math.floor(count / 2);
  return count;
}
