INSERT INTO site_images (slot_key, image_url)
VALUES ('spec_icon:druid_cat:cat', 'druid-cat.png')
ON CONFLICT (slot_key) DO UPDATE
SET image_url = 'druid-cat.png';
