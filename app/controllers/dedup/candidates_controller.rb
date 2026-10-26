# Review queue for cross-source duplicate candidates found by
# Dedup::Scanner — the sibling of PendingDuplicateMergesController for
# already-posted pairs (monarch-import vs provider sync, or two sources
# for one account). Merges run through Dedup::Merger; dismissals persist
# as Dedup::Dismissal so a rejected pair never resurfaces.
class Dedup::CandidatesController < ApplicationController
  PAGE_SIZE = 20

  def index
    @breadcrumbs = [
      [ t("breadcrumbs.home"), root_path ],
      [ t("breadcrumbs.transactions"), transactions_path ],
      [ t(".title"), nil ]
    ]
    @confidence_filter = params[:confidence].presence_in(%w[high medium low])
    @include_same_source = params[:same_source] == "1"

    scanner = Dedup::Scanner.new(family: Current.family, include_same_source: @include_same_source)
    @summary = scanner.summary

    list = scanner.candidates
    list = list.select { |c| c.confidence == @confidence_filter.to_sym } if @confidence_filter
    @pagy, @candidates = pagy_array(list, limit: PAGE_SIZE)
    @grouped = @candidates.group_by(&:account)
  end

  def merge
    pair = find_pair or return
    return unless permitted?(pair)

    winner = Dedup.preferred_entry(*pair)
    loser = pair.reject { |e| e.id == winner.id }.first

    if Dedup::Merger.new(winner: winner, loser: loser).merge!
      redirect_to dedup_candidates_path, notice: t(".merged", name: winner.name)
    else
      redirect_to dedup_candidates_path, alert: t(".merge_failed")
    end
  end

  def dismiss
    pair = find_pair or return
    return unless permitted?(pair)

    Dedup::Dismissal.dismiss!(family: Current.family, entry_a: pair.first, entry_b: pair.second)
    redirect_to dedup_candidates_path, notice: t(".dismissed")
  end

  private
    def find_pair
      a = Current.accessible_entries.find_by(id: params[:entry_a_id])
      b = Current.accessible_entries.find_by(id: params[:entry_b_id])
      unless a && b && a.id != b.id &&
             a.entryable.is_a?(Transaction) && b.entryable.is_a?(Transaction)
        redirect_to dedup_candidates_path, alert: t("dedup.candidates.shared.invalid_pair")
        return nil
      end
      [ a, b ]
    end

    def permitted?(pair)
      pair.all? do |entry|
        require_account_permission!(entry.account, :annotate, redirect_path: dedup_candidates_path)
      end
    end
end
