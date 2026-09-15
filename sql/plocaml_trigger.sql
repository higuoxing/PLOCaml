-- Ported from PostgreSQL src/pl/plpython/sql/plpython_trigger.sql (REL_16_STABLE).
-- these triggers are dedicated to HPHC of RI who
-- decided that my kid's name was william not willem, and
-- vigorously resisted all efforts at correction.  they have
-- since gone bankrupt...
--
-- TD is not yet exposed; functions return Skip/Modify analogs as strings.

CREATE FUNCTION users_insert() RETURNS trigger
	AS $$
PL.String "SKIP"
$$ LANGUAGE plocamlu;


CREATE FUNCTION users_update() RETURNS trigger
	AS $$
PL.Null
$$ LANGUAGE plocamlu;


CREATE FUNCTION users_delete() RETURNS trigger
	AS $$
PL.String "SKIP"
$$ LANGUAGE plocamlu;


CREATE TRIGGER users_insert_trig BEFORE INSERT ON users FOR EACH ROW
	EXECUTE PROCEDURE users_insert ('willem');

CREATE TRIGGER users_update_trig BEFORE UPDATE ON users FOR EACH ROW
	EXECUTE PROCEDURE users_update ('willem');

CREATE TRIGGER users_delete_trig BEFORE DELETE ON users FOR EACH ROW
	EXECUTE PROCEDURE users_delete ('willem');


-- quick peek at the table
--
SELECT * FROM users;

-- should fail
--
UPDATE users SET fname = 'william' WHERE fname = 'willem';

-- should modify william to willem and create username
--
INSERT INTO users (fname, lname) VALUES ('william', 'smith');
INSERT INTO users (fname, lname, username) VALUES ('charles', 'darwin', 'beagle');

SELECT * FROM users;


-- dump trigger data

CREATE TABLE trigger_test
	(i int, v text );

CREATE TABLE trigger_test_generated (
	i int,
        j int GENERATED ALWAYS AS (i * 2) STORED
);

CREATE FUNCTION trigger_data() RETURNS trigger LANGUAGE plocamlu AS $$
PL.Null
$$;

CREATE TRIGGER show_trigger_data_trig_before
BEFORE INSERT OR UPDATE OR DELETE ON trigger_test
FOR EACH ROW EXECUTE PROCEDURE trigger_data(23,'skidoo');

CREATE TRIGGER show_trigger_data_trig_after
AFTER INSERT OR UPDATE OR DELETE ON trigger_test
FOR EACH ROW EXECUTE PROCEDURE trigger_data(23,'skidoo');

CREATE TRIGGER show_trigger_data_trig_stmt
BEFORE INSERT OR UPDATE OR DELETE OR TRUNCATE ON trigger_test
FOR EACH STATEMENT EXECUTE PROCEDURE trigger_data(23,'skidoo');

insert into trigger_test values(1,'insert');
update trigger_test set v = 'update' where i = 1;
delete from trigger_test;
truncate table trigger_test;
