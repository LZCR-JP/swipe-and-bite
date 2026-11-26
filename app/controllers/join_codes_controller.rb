# Public "enter your code" screen for teammates joining without a link.
class JoinCodesController < ApplicationController
  rate_limit to: 10, within: 1.minute, only: :create,
             with: -> { redirect_to join_code_path, alert: "Too many attempts. Please wait a minute and try again." }

  def new
    @code = params[:code]
  end

  def create
    @code = (params[:code] || params.dig(:join, :code)).to_s.strip
    nomikai = Nomikai.find_by_join_code(@code)

    @error =
      if @code.blank?
        "Enter the code your host shared with you."
      elsif nomikai.nil?
        "We couldn't find an event with that code. Double-check it with your host. It may have been replaced."
      elsif !nomikai.accepting_participants?
        "This event is no longer accepting new teammates."
      end

    return redirect_to join_with_code_path(nomikai.formatted_join_code) if @error.nil?

    render :new, status: :unprocessable_entity
  end
end
