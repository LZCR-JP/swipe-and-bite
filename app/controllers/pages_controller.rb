class PagesController < ApplicationController
  def home
    redirect_to new_nomikai_path
  end

  def about
  end
end
