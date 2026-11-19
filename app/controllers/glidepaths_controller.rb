class GlidepathsController < ApplicationController
  def show
    @glidepath = Glidepath.includes(glidepath_steps: :allocation).find(params[:id])
    @steps = @glidepath.glidepath_steps.joins(:allocation).order('allocations.avg_nominal_return DESC')
  end
end
