CREATE TABLE IF NOT EXISTS users (
    user_id BIGSERIAL PRIMARY KEY,
    role user_role,

    first_name VARCHAR(128),
    last_name VARCHAR(128),
    email VARCHAR(512) NOT NULL UNIQUE,
    password_hash VARCHAR(256) NOT NULL,

    is_verified BOOLEAN DEFAULT false,

    orders_placed BIGINT DEFAULT 0,

    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS categories (
    category_id BIGSERIAL PRIMARY KEY,

    name VARCHAR(64),
    description VARCHAR(256)
);

CREATE TABLE IF NOT EXISTS items (
    item_id BIGSERIAL PRIMARY KEY,
    category_id BIGINT REFERENCES categories(category_id),
    seller_id BIGINT REFERENCES users(user_id),

    state item_state,

    name VARCHAR(512),
    description VARCHAR(2048),

    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS orders (
    order_id BIGSERIAL PRIMARY KEY,
    customer_id BIGINT REFERENCES users(user_id),
    item_id BIGINT REFERENCES items(item_id),
    items_amount INT,

    address VARCHAR(512),

    ordered_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP,
    delivered_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS shop_stats (
    users_amount BIGINT,
    items_amount BIGINT,
    orders_amount BIGINT
);