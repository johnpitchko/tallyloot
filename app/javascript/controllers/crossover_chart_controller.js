import { Controller } from "@hotwired/stimulus";
import ApexCharts from "apexcharts";
import { formatCurrency } from "utils/currency";
import { chartBase, gridTheme, xaxisLabels, yaxisLabels, legendTheme } from "utils/chart_theme";

// Connects to data-controller="crossover-chart"
export default class extends Controller {
  static targets = ["userFilter", "chartContainer", "subtitle"];
  static values = {
    crossoverData: Array,
    users: Array,
  };

  connect() {
    const data = this.dataForUser("all");
    this.renderChart(data);
    this.updateSubtitle(data);
  }

  disconnect() {
    this.chart?.destroy();
  }

  updateChart() {
    const selectedUserId = this.userFilterTarget.value;
    const userId = selectedUserId === "all" ? "all" : parseInt(selectedUserId);
    const data = this.dataForUser(userId);

    this.chart?.destroy();
    this.renderChart(data);
    this.updateSubtitle(data);
  }

  dataForUser(userId) {
    return this.crossoverDataValue.find((d) => d.user_id === userId) || this.crossoverDataValue[0];
  }

  updateSubtitle(data) {
    if (data.crossover_year && data.crossover_year <= new Date().getFullYear()) {
      this.subtitleTarget.innerHTML = "<strong>You have already passed your crossover point — your investments are now growing faster than you are contributing.</strong>";
    } else if (data.crossover_year) {
      this.subtitleTarget.innerHTML = `Crossover point: <strong>${data.crossover_year} at ${formatCurrency(data.crossover_amount)}/yr</strong>`;
    } else {
      this.subtitleTarget.innerHTML = "No crossover point is reached before retirement in this projection.";
    }
  }

  renderChart(data) {
    const annotations = data.crossover_year
      ? {
          xaxis: [{
            x: data.crossover_year,
            borderColor: "#a0a0a0",
            strokeDashArray: 4,
            label: { text: "Crossover", style: { color: "#f5f5f5", background: "#2f2f2f" } },
          }],
        }
      : {};

    const options = {
      chart: { ...chartBase, type: "line", height: 320 },
      series: [
        { name: "Contributions", data: data.contributions },
        { name: "Growth", data: data.growth },
      ],
      xaxis: { categories: data.years, labels: xaxisLabels() },
      yaxis: { labels: yaxisLabels() },
      colors: ["#f59e0b", "#4ae087"],
      stroke: { width: 3, curve: "smooth" },
      grid: gridTheme,
      legend: legendTheme(),
      markers: { size: 0 },
      annotations,
      tooltip: {
        theme: "dark",
        shared: true,
        intersect: false,
        followCursor: true,
        y: { formatter: (value) => formatCurrency(value) },
      },
    };

    this.chart = new ApexCharts(this.chartContainerTarget, options);
    this.chart.render();
  }
}
