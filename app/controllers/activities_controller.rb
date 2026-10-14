class ActivitiesController < ApplicationController
  before_action :set_activity, only: [ :show, :edit, :update, :destroy ]
  before_action :set_selectable_oshis, only: [ :index, :new, :create, :edit, :update ]

  def index
    @filters = {}
    @filter_errors = []
    %w[month oshi_id activity_type q].each do |key|
      value = params[key]
      if value.nil? || value.is_a?(String)
        @filters[key] = value.to_s
      else
        @filters[key] = ""
        @filter_errors << "検索条件の形式が正しくありません。"
      end
    end
    scope = current_user.activities
    month = @filters["month"]
    if month.present?
      begin
        raise ArgumentError unless month.match?(/\A[0-9]{4}-(0[1-9]|1[0-2])\z/) && month[0, 4].to_i.positive?
        first = Date.strptime(month, "%Y-%m")
        scope = scope.where(occurred_on: first...first.next_month)
      rescue ArgumentError
        @filter_errors << "年月はYYYY-MM形式で指定してください。"
      end
    end
    if @filters["oshi_id"].present?
      id = positive_id(@filters["oshi_id"])
      if id && @selectable_oshis.any? { |oshi| oshi.id == id }
        scope = scope.joins(:activity_oshis).where(activity_oshis: { oshi_id: id }).distinct
      else
        @filter_errors << "登録済みの推しを選択してください。"
      end
    end
    category = @filters["activity_type"]
    if category.present?
      if Activity::ACTIVITY_TYPES.include?(category)
        scope = scope.where(activity_type: category)
      else
        @filter_errors << "カテゴリが正しくありません。"
      end
    end
    if @filters["q"].present?
      pattern = "%#{Activity.sanitize_sql_like(@filters['q'])}%"
      scope = scope.where("activities.title ILIKE :query OR activities.place ILIKE :query OR activities.memo ILIKE :query", query: pattern)
    end
    @activities = (@filter_errors.empty? ? scope : scope.none).order(occurred_on: :desc, created_at: :desc, id: :desc)
    render :index, status: :bad_request if @filter_errors.any?
  end

  def new
    @activity = current_user.activities.new
    @selected_oshi_ids = []
    @existing_images = []
  end

  def create
    @activity = current_user.activities.new
    @existing_images = []
    if save_activity
      redirect_to activities_path, notice: "活動記録を登録しました。", status: :see_other
    else
      render :new, status: :unprocessable_content
    end
  end

  def show
    @activity.oshis.load
  end

  def edit
    @selected_oshi_ids = @activity.oshi_ids
  end

  def update
    if save_activity
      redirect_to activity_path(@activity), notice: "活動記録を更新しました。", status: :see_other
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    destroy_activity
    redirect_to activities_path, notice: "活動記録を削除しました。", status: :see_other
  rescue ActiveRecord::RecordNotDestroyed
    redirect_to activity_path(@activity), alert: "活動記録を削除できませんでした。", status: :see_other
  end

  private

    def set_activity
      @activity = current_user.activities.with_attached_images.find(params[:id])
      @existing_images = @activity.images.attachments.to_a
    rescue ActiveRecord::RecordNotFound => error
      render_user_data_not_found(error)
    end

    def set_selectable_oshis
      @selectable_oshis = current_user.oshis.order(:name, :id).to_a
    end

    def positive_id(value)
      value.to_i if value.is_a?(String) && value.match?(/\A[1-9][0-9]*\z/)
    end

    def save_activity
      input = params.require(:activity)
      raise ActionController::BadRequest unless input.is_a?(ActionController::Parameters)
      attributes = input.permit(:occurred_on, :activity_type, :title, :place, :amount, :memo)
      raw_ids = input[:oshi_ids] || []
      @selected_oshi_ids = []
      ids_valid = raw_ids.is_a?(Array) && raw_ids.all? { |id| id == "" || positive_id(id) }
      @selected_oshi_ids = raw_ids.reject { |id| id == "" }.map { |id| positive_id(id) }.uniq if ids_valid
      uploads = input[:images] || []
      images_valid = uploads.is_a?(Array) && uploads.all? { |image| image == "" || image.is_a?(ActionDispatch::Http::UploadedFile) }
      allowed = @selectable_oshis.map(&:id)
      selection_valid = ids_valid && (@selected_oshi_ids - allowed).empty?
      if !selection_valid || @selected_oshi_ids.empty? || !images_valid
        @activity.assign_attributes(attributes)
        @activity.errors.add(:base, "登録済みの推しを正しい形式で選択してください。") unless selection_valid
        @activity.errors.add(:base, "推しを1件以上選択してください") if ids_valid && @selected_oshi_ids.empty?
        @activity.errors.add(:images, "はファイルとして選択してください。") unless images_valid
        return false
      end
      Activities::Save.call(activity: @activity, attributes: attributes, oshi_ids: @selected_oshi_ids, new_images: uploads.reject { |image| image == "" })
      true
    rescue ActiveRecord::RecordInvalid
      false
    end

    def destroy_activity
      @activity.with_lock do
        # Only whole-record deletion bypasses the last-oshi protection.
        ActivityOshi.where(activity_id: @activity.id).delete_all
        @activity.destroy!
      end
    end
end
