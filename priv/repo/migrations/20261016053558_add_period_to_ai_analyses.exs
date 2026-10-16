defmodule Grana.Repo.Migrations.AddPeriodToAiAnalyses do
  use Ecto.Migration

  # The dashboard shows one analysis per period (month, or whole year as month 0).
  # Analyses made for the whole period keep their period here; the ones made with bank,
  # source or movement filters, or with a question, stay only in filters_json.
  def up do
    alter table(:ai_analyses) do
      add :year, :integer
      add :month, :integer
    end

    create index(:ai_analyses, [:user_id, :year, :month])

    execute """
    UPDATE ai_analyses
    SET year = CAST(json_extract(filters_json, '$.year') AS INTEGER),
        month = COALESCE(CAST(json_extract(filters_json, '$.month') AS INTEGER), 0)
    WHERE json_extract(filters_json, '$.year') IS NOT NULL
      AND COALESCE(json_extract(filters_json, '$.bank'), 'all') = 'all'
      AND COALESCE(json_extract(filters_json, '$.type'), 'all') = 'all'
      AND COALESCE(json_extract(filters_json, '$.statement_type'), 'all') = 'all'
      AND (prompt IS NULL OR prompt = '')
      AND json_extract(result_json, '$.nota') IS NOT NULL
    """
  end

  def down do
    drop index(:ai_analyses, [:user_id, :year, :month])

    alter table(:ai_analyses) do
      remove :year
      remove :month
    end
  end
end
