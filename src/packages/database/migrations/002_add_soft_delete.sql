DO $$ 
BEGIN 
    -- Only add column if it doesn't exist
    IF NOT EXISTS (
        SELECT 1 
        FROM information_schema.columns 
        WHERE table_name = 'messages' 
        AND column_name = 'deleted_at'
    ) THEN
        ALTER TABLE messages 
        ADD COLUMN deleted_at TIMESTAMP WITH TIME ZONE DEFAULT NULL;
    END IF;

    -- Drop view if exists before creating
    DROP VIEW IF EXISTS active_messages;
    
    CREATE VIEW active_messages AS
    SELECT * FROM messages WHERE deleted_at IS NULL;
END $$; 