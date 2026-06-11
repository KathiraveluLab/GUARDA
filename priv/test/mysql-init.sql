CREATE DATABASE IF NOT EXISTS guarda_test_mysql;
USE guarda_test_mysql;
CREATE TABLE clinics (id INT AUTO_INCREMENT PRIMARY KEY, name VARCHAR(50));
INSERT INTO clinics (name) VALUES ('Bob Clinic');
