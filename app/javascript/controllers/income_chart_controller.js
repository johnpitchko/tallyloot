import { Controller } from "@hotwired/stimulus";
import ApexCharts from "apexcharts";
import { formatCurrency } from "utils/currency";
import { chartBase, gridTheme, xaxisLabels, yaxisLabels, legendTheme, CHART_COLORS } from "utils/chart_theme";

// Connects to data-controller="income-chart"
export default class extends Controller {
  static targets = [
    "userFilter",
    "summaryChartContainer",
    "breakdownChartContainer",
    "nominalBtn",
    "realBtn",
    "grossBtn",
    "netBtn",
  ];
  static values = {
    labels: Array,
    incomeData: Object,
    realIncomeData: Object,
    users: Array,
  };

  connect() {
    this.mode = "nominal";
    this.incomeView = "gross";
    this.createCharts();
  }

  disconnect() {
    this.summaryChart?.destroy();
    this.breakdownChart?.destroy();
  }

  filter() {
    this.destroyCharts();
    this.createCharts();
  }

  toggleDollars(event) {
    this.mode = event.params.mode;
    this.nominalBtnTarget.classList.toggle("is-selected", this.mode === "nominal");
    this.nominalBtnTarget.classList.toggle("is-primary", this.mode === "nominal");
    this.realBtnTarget.classList.toggle("is-selected", this.mode === "real");
    this.realBtnTarget.classList.toggle("is-primary", this.mode === "real");
    this.destroyCharts();
    this.createCharts();
  }

  toggleIncomeView(event) {
    this.incomeView = event.params.view;
    this.grossBtnTarget.classList.toggle("is-selected", this.incomeView === "gross");
    this.grossBtnTarget.classList.toggle("is-primary", this.incomeView === "gross");
    this.netBtnTarget.classList.toggle("is-selected", this.incomeView === "net");
    this.netBtnTarget.classList.toggle("is-primary", this.incomeView === "net");
    this.destroyCharts();
    this.createCharts();
  }

  destroyCharts() {
    this.summaryChart?.destroy();
    this.breakdownChart?.destroy();
  }

  getFilteredData() {
    const selectedUserId = this.userFilterTarget.value;
    const incomeData = this.mode === "real" ? this.realIncomeDataValue : this.incomeDataValue;
    const showOwnerNames = selectedUserId === "all";
    const showNet = this.incomeView === "net" && selectedUserId === "all";

    let filteredWithdrawals, filteredEmployments, filteredPensions, filteredBenefits, totalIncome;

    if (selectedUserId === "all") {
      filteredWithdrawals = incomeData.withdrawals;
      filteredEmployments = incomeData.employments || [];
      filteredPensions = incomeData.pensions;
      filteredBenefits = incomeData.benefits;
      totalIncome = showNet ? incomeData.net_total_income : incomeData.total_income;
    } else {
      const userId = parseInt(selectedUserId);
      filteredWithdrawals = incomeData.withdrawals.filter((item) => item.user_id === userId);
      filteredEmployments = (incomeData.employments || []).filter((item) => item.user_id === userId);
      filteredPensions = incomeData.pensions.filter((item) => item.user_id === userId);
      filteredBenefits = incomeData.benefits.filter((item) => item.user_id === userId);

      const numPeriods = this.labelsValue.length;
      totalIncome = Array(numPeriods).fill(0);

      for (let i = 0; i < numPeriods; i++) {
        filteredWithdrawals.forEach((item) => { totalIncome[i] += item.data[i] || 0; });
        filteredEmployments.forEach((item) => { totalIncome[i] += item.data[i] || 0; });
        filteredPensions.forEach((item) => { totalIncome[i] += item.data[i] || 0; });
        filteredBenefits.forEach((item) => { totalIncome[i] += item.data[i] || 0; });
      }
    }

    // Income goal is household-level — only show for "all" filter
    const incomeGoal = selectedUserId === "all" && incomeData.income_goal ? incomeData.income_goal : null;

    // Tax series only available for household view
    const estimatedTax = showNet && incomeData.estimated_tax ? incomeData.estimated_tax : null;

    return { withdrawals: filteredWithdrawals, employments: filteredEmployments, pensions: filteredPensions, benefits: filteredBenefits, totalIncome, incomeGoal, estimatedTax, showOwnerNames, showNet };
  }

  xaxisConfig() {
    return { categories: this.labelsValue, labels: xaxisLabels() };
  }

  yaxisConfig() {
    return { labels: yaxisLabels() };
  }

  tooltipConfig() {
    return {
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
          if (value !== null && value !== undefined && value > 0) {
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
    };
  }

  createCharts() {
    const data = this.getFilteredData();
    this.createSummaryChart(data);
    this.createBreakdownChart(data);
  }

  createSummaryChart({ totalIncome, incomeGoal, showNet }) {
    const hasGoal = incomeGoal && incomeGoal.some((v) => v !== null && v > 0);
    const incomeName = showNet ? "Net Income" : "Total Income";

    const series = [
      { name: incomeName, data: totalIncome },
      ...(hasGoal ? [{ name: "Income Goal", data: incomeGoal }] : []),
    ];

    const options = {
      chart: { ...chartBase, type: "line", height: 280 },
      series,
      xaxis: this.xaxisConfig(),
      yaxis: this.yaxisConfig(),
      grid: gridTheme,
      tooltip: this.tooltipConfig(),
      stroke: { width: [3, ...(hasGoal ? [3] : [])], curve: "smooth", dashArray: 0 },
      fill: {},
      legend: legendTheme(),
      colors: ["#4ae087", ...(hasGoal ? ["#f59e0b"] : [])],
      markers: { size: 0 },
    };

    this.summaryChart = new ApexCharts(this.summaryChartContainerTarget, options);
    this.summaryChart.render();
  }

  createBreakdownChart({ withdrawals, employments, pensions, benefits, showOwnerNames, totalIncome, estimatedTax, showNet }) {
    const numSources = withdrawals.length + (employments || []).length + pensions.length + benefits.length;
    const incomeName = showNet ? "Net Income" : "Total Income";

    const sourceSeries = [
      ...withdrawals.map((item) => ({
        name: showOwnerNames ? `${item.name} Withdrawal (${item.user_name})` : `${item.name} Withdrawal`,
        type: "bar",
        data: item.data,
      })),
      ...(employments || []).map((item) => ({
        name: showOwnerNames ? `${item.name} (${item.user_name})` : item.name,
        type: "bar",
        data: item.data,
      })),
      ...pensions.map((item) => ({
        name: showOwnerNames ? `${item.name} (${item.user_name})` : item.name,
        type: "bar",
        data: item.data,
      })),
      ...benefits.map((item) => ({
        name: showOwnerNames ? `${item.name} (${item.user_name})` : item.name,
        type: "bar",
        data: item.data,
      })),
    ];

    const taxSeries = estimatedTax ? [{ name: "Est. Tax", type: "bar", data: estimatedTax }] : [];
    const series = [...sourceSeries, ...taxSeries, { name: incomeName, type: "line", data: totalIncome }];
    const numBars = numSources + taxSeries.length;

    const barColors = Array.from({ length: numSources }, (_, i) => CHART_COLORS[i % CHART_COLORS.length]);
    const taxColor = estimatedTax ? ["#f97316"] : [];

    const options = {
      chart: { ...chartBase, type: "line", height: 400, stacked: true, stackOnlyBar: true },
      series,
      xaxis: this.xaxisConfig(),
      yaxis: this.yaxisConfig(),
      grid: gridTheme,
      tooltip: this.tooltipConfig(),
      dataLabels: { enabled: false },
      plotOptions: { bar: { columnWidth: "60%" } },
      stroke: { width: [...Array(numBars).fill(0), 3], curve: "smooth" },
      fill: { opacity: [...Array(numBars).fill(0.85), 1] },
      legend: legendTheme(),
      colors: [...barColors, ...taxColor, "#4ae087"],
      markers: { size: 0 },
    };

    this.breakdownChart = new ApexCharts(this.breakdownChartContainerTarget, options);
    this.breakdownChart.render();
  }
}
