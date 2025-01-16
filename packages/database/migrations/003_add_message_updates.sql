DO $$ 
BEGIN 
    -- Add updated_at column if it doesn't exist
    IF NOT EXISTS (
        SELECT 1 
        FROM information_schema.columns 
        WHERE table_name = 'messages' 
        AND column_name = 'updated_at'
    ) THEN
        ALTER TABLE messages 
        ADD COLUMN updated_at TIMESTAMP WITH TIME ZONE;

        -- Update existing rows to have updated_at same as created_at
        UPDATE messages 
        SET updated_at = created_at 
        WHERE updated_at IS NULL;

        -- Make updated_at NOT NULL and set default
        ALTER TABLE messages 
        ALTER COLUMN updated_at SET NOT NULL,
        ALTER COLUMN updated_at SET DEFAULT CURRENT_TIMESTAMP;
    END IF;
END $$; 