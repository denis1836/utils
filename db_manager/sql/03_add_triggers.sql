CREATE OR REPLACE FUNCTION update_shop_stats()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_TABLE_NAME = 'users' THEN
        UPDATE shop_stats SET users_amount = users_amount + 1;
    ELSIF TG_TABLE_NAME = 'items' THEN
        UPDATE shop_stats SET items_amount = items_amount + 1;
    ELSIF TG_TABLE_NAME = 'orders' THEN
        UPDATE shop_stats SET orders_amount = orders_amount + 1;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER user_created
    AFTER INSERT ON users
    FOR EACH ROW
    EXECUTE FUNCTION update_shop_stats();

CREATE TRIGGER item_added
    AFTER INSERT ON items
    FOR EACH ROW
    EXECUTE FUNCTION update_shop_stats();

CREATE TRIGGER order_created
    AFTER INSERT ON orders
    FOR EACH ROW
    EXECUTE FUNCTION update_shop_stats();