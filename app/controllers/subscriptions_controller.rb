class SubscriptionsController < ApplicationController
  before_action :set_subscription, only: [ :edit, :update, :destroy ]
  before_action :set_selectable_oshis, only: [ :new, :create, :edit, :update ]

  def index
    @date = Date.current
    @subscriptions = current_user.subscriptions.includes(:oshis).order(created_at: :desc, id: :desc)
  end

  def new
    @subscription = current_user.subscriptions.new
    @selected_oshi_ids = []
  end

  def create
    @subscription = current_user.subscriptions.new
    if save_subscription
      redirect_to subscriptions_path, notice: "固定費を登録しました。", status: :see_other
    else
      render :new, formats: [ :html ], status: :unprocessable_content
    end
  end

  def edit
    @selected_oshi_ids = @subscription.oshi_ids
  end

  def update
    if save_subscription
      redirect_to subscriptions_path, notice: "固定費を更新しました。", status: :see_other
    else
      render :edit, formats: [ :html ], status: :unprocessable_content
    end
  end

  def destroy
    @subscription.with_lock do
      @subscription.subscription_oshis.each(&:destroy!)
      @subscription.destroy!
    end
    redirect_to subscriptions_path, notice: "固定費を削除しました。", status: :see_other
  rescue ActiveRecord::RecordNotDestroyed
    redirect_to subscriptions_path, alert: "固定費を削除できませんでした。", status: :see_other
  end

  private

    def set_subscription
      @subscription = current_user.subscriptions.find(params[:id])
    rescue ActiveRecord::RecordNotFound => error
      render_user_data_not_found(error)
    end

    def set_selectable_oshis
      @selectable_oshis = current_user.oshis.order(:name, :id).to_a
    end

    def save_subscription
      input = params.require(:subscription)
      raise ActionController::BadRequest unless input.is_a?(ActionController::Parameters)
      attributes = input.permit(:name, :amount, :billing_cycle, :started_on, :ended_on)
      raw_ids = input.key?(:oshi_ids) ? input[:oshi_ids] : []
      @selected_oshi_ids = []
      valid_shape = raw_ids.is_a?(Array) && raw_ids.all? { |id| id.is_a?(String) && (id.blank? || id.match?(/\A[1-9][0-9]*\z/)) }
      @selected_oshi_ids = raw_ids.reject(&:blank?).map(&:to_i).uniq if valid_shape
      unless valid_shape && (@selected_oshi_ids - @selectable_oshis.map(&:id)).empty?
        @subscription.assign_attributes(attributes)
        @subscription.errors.add(:base, "対象の推しは登録済みの推しを正しい形式で選択してください。")
        return false
      end
      Subscriptions::Save.call(subscription: @subscription, attributes: attributes, oshi_ids: @selected_oshi_ids)
      true
    rescue ActiveRecord::RecordInvalid => error
      @subscription.errors.add(:base, "対象の推しを保存できませんでした。#{error.record.errors.full_messages.join('、')}") unless error.record == @subscription
      false
    rescue ActiveRecord::RecordNotSaved, ActiveRecord::RecordNotDestroyed
      @subscription.errors.add(:base, "固定費と対象の推しを保存できませんでした。")
      false
    end
end
