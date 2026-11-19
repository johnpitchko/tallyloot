import { Controller } from "@hotwired/stimulus";
import ApexCharts from "apexcharts";
import { formatCurrency } from "utils/currency";
import { chartBase, gridTheme, xaxisLabels, yaxisLabels, legendTheme, CHART_COLORS } from "utils/chart_theme";

// Connects to data-controller="chart"
export default class extends Controller {
  static targets = ["userFilter", "chartContainer"];
  static values = {
    labels: Array,
    accountData: Array,
    users: Array,
  };

  connect() {
    this.createChart();
  }

  disconnect() {
    this.chart?.destroy();
  }

  filter() {
    this.chart?.destroy();
    this.createChart();
  }

  getFilteredData() {
    const selectedUserId = this.userFilterTarget.value;
    const showOwnerNames = selectedUserId === "all";

    let filteredAccounts;
    if (selectedUserId === "all") {
      filteredAccounts = this.accountDataValue;
    } else {
      const userId = parseInt(selectedUserId);
      filteredAccounts = this.accountDataValue.filter(
        (account) => account.user_id === userId,
      );
    }

    // Always calculate net worth from account data for consistency
    const netWorthData = this.labelsValue.map((_, periodIndex) => {
      return filteredAccounts.reduce((sum, account) => {
        return sum + (account.data[periodIndex] || 0);
      }, 0);
    });

    return { accountData: filteredAccounts, netWorthData, showOwnerNames };
  }

  createChart() {
    const { accountData, netWorthData, showOwnerNames } = this.getFilteredData();

    // Build series: stacked bars per account + net worth line
    const series = [
      ...accountData.map((account) => ({
        name: showOwnerNames ? `${account.name} (${account.user_name})` : account.name,
        type: "bar",
        data: account.data,
      })),
      { name: "Net Worth", type: "line", data: netWorthData },
    ];

    const numAccounts = accountData.length;
    const strokeWidths = [...Array(numAccounts).fill(0), 3];
    const fillOpacities = [...Array(numAccounts).fill(0.85), 0.2];
    const fillTypes = [...Array(numAccounts).fill("solid"), "gradient"];

    // Account bars cycle through palette; net worth line is always the primary green
    const accountColors = Array.from({ length: numAccounts }, (_, i) => CHART_COLORS[i % CHART_COLORS.length]);
    const colors = [...accountColors, "#4ae087"];

    const options = {
      chart: { ...chartBase, type: "line", height: 400, stacked: true },
      series,
      xaxis: { categories: this.labelsValue, labels: xaxisLabels() },
      yaxis: { labels: yaxisLabels() },
      grid: gridTheme,
      tooltip: {
        theme: "dark",
        shared: true,
        intersect: false,
        followCursor: true,
        custom: ({ series, dataPointIndex, w }) => {
          const year = this.labelsValue[dataPointIndex];
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
      stroke: { width: strokeWidths, curve: "smooth" },
      plotOptions: { bar: { columnWidth: "60%" } },
      fill: {
        opacity: fillOpacities,
        type: fillTypes,
        gradient: {
          shade: "dark",
          type: "vertical",
          shadeIntensity: 0.5,
          gradientToColors: undefined,
          inverseColors: true,
          opacityFrom: 0.7,
          opacityTo: 0.2,
          stops: [0, 100],
        },
      },
      legend: legendTheme(),
      colors,
    };

    this.chart = new ApexCharts(this.chartContainerTarget, options);
    this.chart.render();
  }
}
