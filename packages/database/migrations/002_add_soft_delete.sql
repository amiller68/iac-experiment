ALTER TABLE messages 
ADD COLUMN deleted_at TIMESTAMP WITH TIME ZONE DEFAULT NULL;

-- Update existing queries to exclude deleted messages
CREATE OR REPLACE VIEW active_messages AS
SELECT * FROM messages WHERE deleted_at IS NULL; 