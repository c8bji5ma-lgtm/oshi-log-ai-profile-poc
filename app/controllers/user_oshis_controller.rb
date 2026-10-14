class UserOshisController < ApplicationController
  before_action :set_user_oshi, only: [ :show, :edit, :update ]

  def index
    @user_oshis = current_user.user_oshis.includes(:oshi).order(:id)
  end

  def show
  end

  def edit
  end

  def create
    oshi = Oshi.visible_to(current_user).find(params.require(:oshi_id))
    @existing_user_oshi = current_user.user_oshis.new(started_period_params.merge(oshi: oshi))

    if @existing_user_oshi.save
      redirect_to oshis_path, notice: "推しを登録しました。", status: :see_other
    elsif @existing_user_oshi.errors.of_kind?(:oshi_id, :taken)
      redirect_duplicate
    else
      @oshi = Oshi.new
      @user_oshi = current_user.user_oshis.new
      @oshis = Oshi.visible_to(current_user).search(params[:q]).order(:name, :id)
      # Keep the selected, still-visible candidate available after a failed POST.
      @oshis = Oshi.visible_to(current_user).where(id: oshi.id) if @oshis.empty?
      render "oshis/new", status: :unprocessable_content
    end
  rescue ActiveRecord::RecordNotUnique
    redirect_duplicate
  rescue ActiveRecord::RecordNotFound => error
    render_user_data_not_found(error)
  end

  def update
    attributes = user_oshi_params
    attributes.delete(:representative_image) if attributes[:representative_image].blank?
    if attributes.key?(:representative_image) && !attributes[:representative_image].is_a?(ActionDispatch::Http::UploadedFile)
      @user_oshi.errors.add(:representative_image, "はファイルとして選択してください。")
      render :edit, status: :unprocessable_content
      return
    end
    if @user_oshi.update(attributes)
      redirect_to oshis_path, notice: "推し情報を更新しました。", status: :see_other
    else
      render :edit, status: :unprocessable_content
    end
  end

  private

    def set_user_oshi
      @user_oshi = current_user.user_oshis.find(params[:id])
      @representative_image = @user_oshi.representative_image.attachment
    rescue ActiveRecord::RecordNotFound => error
      render_user_data_not_found(error)
    end

    def started_period_params
      params.fetch(:user_oshi, ActionController::Parameters.new).permit(:started_period)
    end

    def user_oshi_params
      params.require(:user_oshi).permit(:started_period, :ended_period, :representative_image)
    end

    def redirect_duplicate
      redirect_to oshis_path, alert: "この推しはすでに登録されています。", status: :see_other
    end
end
