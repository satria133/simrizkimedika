-- Identitas & tema Rizki Medika untuk mLITE
-- Docker (cloud): dijalankan OTOMATIS saat database pertama kali dibuat (lihat docker-compose.prod.yaml).
-- Manual: mysql -u root -p mlite_db < docs/rizkimedika/setup.sql   (setelah mlite_db.sql diimpor)
UPDATE `mlite_settings` SET `value` = 'Rizki Medika'                 WHERE `module` = 'settings' AND `field` = 'nama_instansi';
UPDATE `mlite_settings` SET `value` = 'Jl. D.I. Panjaitan No. 2B'    WHERE `module` = 'settings' AND `field` = 'alamat';
UPDATE `mlite_settings` SET `value` = 'Pekanbaru'                    WHERE `module` = 'settings' AND `field` = 'kota';
UPDATE `mlite_settings` SET `value` = 'Riau'                         WHERE `module` = 'settings' AND `field` = 'propinsi';
UPDATE `mlite_settings` SET `value` = '(0761) 29243'                 WHERE `module` = 'settings' AND `field` = 'nomor_telepon';
UPDATE `mlite_settings` SET `value` = 'Asia/Jakarta'                 WHERE `module` = 'settings' AND `field` = 'timezone';
UPDATE `mlite_settings` SET `value` = 'rizkimedika'                  WHERE `module` = 'settings' AND `field` = 'theme_admin';
UPDATE `mlite_settings` SET `value` = '#213c9f'                      WHERE `module` = 'settings' AND `field` = 'text_color';
UPDATE `mlite_settings` SET `value` = 'Copyright {?=date("Y")?} &copy; Rizki Medika, Pekanbaru.' WHERE `module` = 'settings' AND `field` = 'footer';
