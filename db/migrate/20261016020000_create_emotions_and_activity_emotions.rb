class CreateEmotionsAndActivityEmotions < ActiveRecord::Migration[8.1]
  def change
    create_table :emotions do |t|
      t.string :name, null: false
      t.integer :position, null: false

      t.timestamps null: false
    end
    add_index :emotions, :name, unique: true

    create_table :activity_emotions do |t|
      t.references :activity, null: false, foreign_key: true
      t.references :emotion, null: false, foreign_key: true

      t.timestamps null: false
    end
    add_index :activity_emotions, [ :activity_id, :emotion_id ], unique: true

    reversible do |direction|
      direction.up do
        execute <<~SQL
          INSERT INTO emotions (name, position, created_at, updated_at) VALUES
            ('嬉しい', 0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
            ('興奮', 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
            ('驚き', 2, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
            ('感動', 3, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
            ('幸せ', 4, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
            ('悔しい', 5, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP),
            ('寂しい', 6, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
        SQL
      end
    end
  end
end
