import { Controller } from "@hotwired/stimulus";
import ApexCharts from "apexcharts";
import { formatCurrency } from "utils/currency";
import { chartBase, gridTheme, xaxisLabels, yaxisLabels, legendTheme } from "utils/chart_theme";

// Connects to data-controller="simulation-chart"
export default class extends Controller {
  static targets = ["chartContainer", "userFilter", "nominalBtn", "realBtn"];
  static values = {
    chartData: Object,
    title: String,
    users: Array,
  };

  connect() {
    this.mode = "nominal";
    this.createChart();
  }

  disconnect() {
    this.chart?.destroy();
  }

  filter() {
    this.chart?.destroy();
    this.createChart();
  }

  toggleDollars(event) {
    this.mode = event.params.mode;
    this.nominalBtnTarget.classList.toggle("is-selected", this.mode === "nominal");
    this.nominalBtnTarget.classList.toggle("is-primary", this.mode === "nominal");
    this.realBtnTarget.classList.toggle("is-selected", this.mode === "real");
    this.realBtnTarget.classList.toggle("is-primary", this.mode === "real");
    this.chart?.destroy();
    this.createChart();
  }

  getChartSeries() {
    const data = this.chartDataValue;
    const isIncome = this.titleValue === "Income";
    const userId = this.hasUserFilterTarget ? this.userFilterTarget.value : "all";

    let current, simulated;

    if (userId === "all") {
      if (isIncome && this.mode === "real") {
        current = data.current_real || data.current;
        simulated = data.simulated_real || data.simulated;
      } else {
        current = data.current;
        simulated = data.simulated;
      }
    } else {
      const userIdInt = parseInt(userId);
      const perUser = (data.per_user || []).find((u) => u.user_id === userIdInt);
      if (!perUser) {
        current = data.current;
        simulated = data.simulated;
      } else if (isIncome && this.mode === "real") {
        current = perUser.current_real || perUser.current;
        simulated = perUser.simulated_real || perUser.simulated;
      } else {
        current = perUser.current;
        simulated = perUser.simulated;
      }
    }

    return [
      { name: "Current", data: current },
      { name: "Simulated", data: simulated },
    ];
  }

  // Returns the income goal series, or null if not applicable.
  // Only shown for the Income chart when viewing the entire household.
  getGoalSeries() {
    const data = this.chartDataValue;
    const isIncome = this.titleValue === "Income";
    const userId = this.hasUserFilterTarget ? this.userFilterTarget.value : "all";

    if (!isIncome || userId !== "all") return null;

    const goalData = this.mode === "real"
      ? data.income_goal_real || data.income_goal
      : data.income_goal;

    if (!goalData || !goalData.some((v) => v > 0)) return null;

    return { name: "Income Goal", data: goalData };
  }

  createChart() {
    const { labels } = this.chartDataValue;
    const series = this.getChartSeries();
    const goalSeries = this.getGoalSeries();
    const allSeries = goalSeries ? [...series, goalSeries] : series;
    const hasGoal = !!goalSeries;

    const options = {
      chart: { ...chartBase, type: "line", height: 300 },
      series: allSeries,
      xaxis: { categories: labels, labels: xaxisLabels() },
      yaxis: { labels: yaxisLabels() },
      grid: gridTheme,
      tooltip: {
        theme: "dark",
        shared: true,
        intersect: false,
        followCursor: true,
        custom: ({ series, dataPointIndex, w }) => {
          const year = labels[dataPointIndex];
          const agesStr = this.usersValue
            .map((user) => `${user.name}: ${year - user.birth_year}`)
            .join(", ");

          let html = '<div style="background: #1e1e1e; border: 1px solid #2f2f2f; padding: 12px; border-radius: 8px;">';
          html += `<div style="font-weight: bold; margin-bottom: 4px; color: #f5f5f5;">${year}</div>`;
          html += `<div style="font-size: 0.85em; margin-bottom: 8px; color: #a0a0a0;">${agesStr}</div>`;

          for (let i = 0; i < series.length; i++) {
            const value = series[i][dataPointIndex];
            if (value !== null && value !== undefined) {
              html += '<div style="display: flex; align-items: center; margin: 4px 0;">';
              html += `<span style="display: inline-block; width: 12px; height: 12px; background: ${w.globals.colors[i]}; margin-right: 8px; border-radius: 2px;"></span>`;
              html += `<span style="color: #f5f5f5; margin-right: 8px;">${w.globals.seriesNames[i]}:</span>`;
              html += `<span style="font-weight: bold; color: #f5f5f5;">${formatCurrency(value)}</span>`;
              html += "</div>";
            }
          }

          html += "</div>";
          return html;
        },
      },
      stroke: {
        width: [3, 3, ...(hasGoal ? [2] : [])],
        curve: "smooth",
        dashArray: [8, 0, ...(hasGoal ? [4] : [])],
      },
      colors: ["#a0a0a0", "#4ae087", ...(hasGoal ? ["#f59e0b"] : [])],
      legend: legendTheme(),
      markers: { size: 0 },
    };

    const container = this.hasChartContainerTarget ? this.chartContainerTarget : this.element;
    this.chart = new ApexCharts(container, options);
    this.chart.render();
  }
}
