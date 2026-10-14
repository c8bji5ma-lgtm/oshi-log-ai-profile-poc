module Admin
  class OshisController < ApplicationController
    before_action :require_admin!

    def index
      @oshis = Oshi.pending.order(:created_at, :id)
    end

    def approve
      update_status(:approved, "推しを承認しました。")
    end

    def reject
      update_status(:rejected, "推しを却下しました。")
    end

    def new_merge
      @oshis = Oshi.order(:name, :id).to_a
    end

    def merge
      input = params.require(:oshi_merge)
      unless input.is_a?(ActionController::Parameters)
        raise Oshis::Merge::InvalidInput, "統合元と統合先を正しく選択してください。"
      end
      attributes = input.permit(:source_id, :target_id)
      target = Oshis::Merge.call(source_id: attributes[:source_id], target_id: attributes[:target_id])
      redirect_to admin_oshis_path, notice: "#{target.name}に推しを統合しました。", status: :see_other
    rescue ActionController::ParameterMissing
      redirect_to new_merge_admin_oshis_path, alert: "統合元と統合先を選択してください。", status: :see_other
    rescue Oshis::Merge::Conflict => error
      label = { started_period: "推し始め", ended_period: "推し終わり", representative_image: "代表画像" }.fetch(error.attribute, "登録情報")
      redirect_to new_merge_admin_oshis_path,
        alert: "ユーザーID：#{error.user_id}の#{label}が競合するため、統合を中止しました。登録内容を確認してください。", status: :see_other
    rescue Oshis::Merge::Error => error
      redirect_to new_merge_admin_oshis_path, alert: error.message, status: :see_other
    rescue ActiveRecord::RecordNotFound
      redirect_to new_merge_admin_oshis_path, alert: "対象の推しが見つかりません。選択し直してください。", status: :see_other
    rescue StandardError => error
      Rails.logger.error("Oshi merge failed: #{error.full_message}")
      redirect_to new_merge_admin_oshis_path, alert: "推しを統合できませんでした。登録内容を確認して再度お試しください。", status: :see_other
    end

    private

      def require_admin!
        return if current_user.admin?

        if html_navigation_request?
          render "errors/forbidden", formats: [ :html ], status: :forbidden
        else
          render plain: "管理者権限が必要です。", status: :forbidden
        end
      end

      def update_status(status, notice)
        oshi = Oshi.find(params[:id])
        updated = oshi.with_lock do
          oshi.pending? && oshi.update!(status: status)
        end

        if updated
          redirect_to admin_oshis_path, notice: notice, status: :see_other
        else
          redirect_to admin_oshis_path, alert: "承認待ちの推しのみ変更できます。一覧を確認してください。", status: :see_other
        end
      rescue ActiveRecord::RecordInvalid
        redirect_to admin_oshis_path, alert: "推しを更新できませんでした。登録内容を確認してください。", status: :see_other
      rescue ActiveRecord::RecordNotFound
        redirect_to admin_oshis_path, alert: "対象の推しが見つかりません。一覧を確認してください。", status: :see_other
      end
  end
end
