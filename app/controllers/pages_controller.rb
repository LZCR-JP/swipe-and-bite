class PagesController < ApplicationController
  def home
    redirect_to new_nomikai_path
  end
end
