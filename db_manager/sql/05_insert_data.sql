INSERT INTO shop_stats (users_amount, items_amount, orders_amount) 
VALUES (0, 0, 0);

INSERT INTO users (role, first_name, last_name, email, password_hash, is_verified)
    VALUES ('admin', 'John', 'Smith', 'john.smith@company.com', '1e20c94e47a33526198023530d65a23ca026fa9a33f4f6caf10b4b8fca1c1223', true);

INSERT INTO categories (name, description) VALUES
('Home', 'Household items'),
('Electronics', 'Gadgets, devices and computers'),
('Books', 'Physical books and e-books'),
('Clothing', 'Clothes, shoes and accessories');