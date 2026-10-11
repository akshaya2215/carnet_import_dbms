# app.py
# -----------------------------------------------------------------------
# Main Flask application for the Indian Vehicle Import Eligibility &
# Carnet Management System.
#
# Public routes:
#   /          â€“ Home page
#   /check     â€“ Submit a new import application
#   /result/<id> â€“ See the eligibility result for an application
#   /rules     â€“ View active eligibility rules
#   /about     â€“ About page
#
# Admin routes (require login):
#   /admin/login   /admin/logout
#   /admin/dashboard
#   /admin/vehicles, /manufacturers, /countries, /applicants,
#   /admin/carnets, /admin/applications, /admin/documents, /admin/rules
#   /admin/results, /admin/reports
# -----------------------------------------------------------------------

from functools import wraps
import mysql.connector
from flask import (
    Flask, render_template, request, redirect,
    url_for, session, flash, g
)
from werkzeug.security import check_password_hash
import config
import db as database

app = Flask(__name__)
app.secret_key = config.SECRET_KEY

# Register the DB teardown so connections close after each request
app.teardown_appcontext(database.close_db)


# ==========================================================================
# LOGIN REQUIRED DECORATOR
# ==========================================================================

def login_required(f):
    """
    Decorator: redirect to the admin login page if the user is not logged in.
    Wrap admin view functions with @login_required.
    """
    @wraps(f)
    def decorated(*args, **kwargs):
        if "admin_id" not in session:
            flash("Please log in to access the admin panel.", "warning")
            return redirect(url_for("admin_login"))
        return f(*args, **kwargs)
    return decorated


# ==========================================================================
# GENERIC CRUD HELPER
# ==========================================================================

def crud_list(table, select_sql, params=None):
    """Return all rows for a table using a custom SELECT."""
    return database.query(select_sql, params)


def crud_get(select_sql, params):
    """Return a single row by primary key."""
    rows = database.query(select_sql, params)
    return rows[0] if rows else None


def crud_insert(table, fields, values):
    """
    Generic INSERT: fields is a list of column names, values a matching list.
    Returns the new row's ID.
    """
    placeholders = ", ".join(["%s"] * len(fields))
    cols = ", ".join(fields)
    sql = f"INSERT INTO `{table}` ({cols}) VALUES ({placeholders})"
    return database.execute(sql, values)


def crud_update(table, fields, values, pk_col, pk_val):
    """
    Generic UPDATE: fields is a list of columns to update.
    values is the list of new values; pk_val is the row ID.
    """
    set_clause = ", ".join([f"`{f}` = %s" for f in fields])
    sql = f"UPDATE `{table}` SET {set_clause} WHERE `{pk_col}` = %s"
    database.execute(sql, values + [pk_val])


def crud_delete(table, pk_col, pk_val):
    """Generic DELETE by primary key."""
    sql = f"DELETE FROM `{table}` WHERE `{pk_col}` = %s"
    database.execute(sql, [pk_val])


def handle_db_error(e):
    """
    Return a friendly flash message for common MySQL errors.
    1062 = duplicate key, 1451/1452 = foreign key violation.
    """
    if e.errno == 1062:
        flash("That record already exists (duplicate value).", "danger")
    elif e.errno in (1451, 1452):
        flash("Cannot complete: a related record depends on this data.", "danger")
    else:
        flash(f"Database error: {e.msg}", "danger")


# ==========================================================================
# PUBLIC ROUTES
# ==========================================================================

@app.route("/")
def index():
    """Home page â€“ show summary statistics."""
    stats = database.query("""
        SELECT
            (SELECT COUNT(*) FROM import_application)               AS total_apps,
            (SELECT COUNT(*) FROM import_application WHERE status='ELIGIBLE') AS eligible,
            (SELECT COUNT(*) FROM import_application WHERE status='REJECTED') AS rejected,
            (SELECT COUNT(*) FROM vehicle)                          AS total_vehicles,
            (SELECT COUNT(*) FROM eligibility_rule WHERE is_active=1) AS active_rules
    """)[0]
    recent = database.query("""
        SELECT ia.application_id, ia.application_date, ia.status,
               ap.full_name, v.model, it.type_name
        FROM import_application ia
        JOIN applicant   ap ON ap.applicant_id   = ia.applicant_id
        JOIN vehicle     v  ON v.vehicle_id      = ia.vehicle_id
        JOIN import_type it ON it.import_type_id = ia.import_type_id
        ORDER BY ia.application_id DESC LIMIT 5
    """)
    return render_template("index.html", stats=stats, recent=recent)


@app.route("/check", methods=["GET", "POST"])
def check():
    """
    Public form: applicant details + vehicle details + optional carnet.
    On POST: wrap everything in ONE transaction, call CheckEligibility,
    then redirect to the result page.
    """
    manufacturers = database.query("SELECT manufacturer_id, name FROM manufacturer ORDER BY name")
    countries     = database.query("SELECT country_id, country_name FROM country ORDER BY country_name")
    import_types  = database.query("SELECT import_type_id, type_name FROM import_type ORDER BY type_name")
    documents     = database.query("SELECT document_id, document_name, is_mandatory FROM document ORDER BY document_name")

    if request.method == "POST":
        f = request.form

        # ---- gather form values ----
        passport      = f.get("passport_number", "").strip()
        full_name     = f.get("full_name", "").strip()
        phone         = f.get("phone", "").strip()
        email         = f.get("email", "").strip()
        address       = f.get("address", "").strip()

        vin           = f.get("vin", "").strip().upper()
        mfr_id        = f.get("manufacturer_id")
        model         = f.get("model", "").strip()
        year          = f.get("manufacture_year")
        fuel          = f.get("fuel_type")
        engine_cc     = f.get("engine_cc") or 0
        steering      = f.get("steering_side")
        origin_cid    = f.get("origin_country_id")

        carnet_number = f.get("carnet_number", "").strip()
        carnet_issue  = f.get("carnet_issue_date", "").strip()
        carnet_expiry = f.get("carnet_expiry_date", "").strip()
        carnet_cid    = f.get("carnet_country_id")

        import_type_id = f.get("import_type_id")
        doc_ids        = request.form.getlist("document_ids")   # list of checked doc IDs

        conn = database.get_db()
        try:

            # 1. Insert or look up applicant by passport number
            existing = database.query(
                "SELECT applicant_id FROM applicant WHERE passport_number = %s",
                (passport,)
            )
            if existing:
                applicant_id = existing[0]["applicant_id"]
            else:
                applicant_id = database.execute(
                    """INSERT INTO applicant (full_name, passport_number, phone, email, address)
                       VALUES (%s, %s, %s, %s, %s)""",
                    (full_name, passport, phone, email, address)
                )

            # 2. Insert vehicle (or look up by VIN)
            existing_veh = database.query(
                "SELECT vehicle_id FROM vehicle WHERE vin = %s", (vin,)
            )
            if existing_veh:
                vehicle_id = existing_veh[0]["vehicle_id"]
            else:
                vehicle_id = database.execute(
                    """INSERT INTO vehicle
                       (vin, manufacturer_id, model, manufacture_year,
                        fuel_type, engine_cc, steering_side, origin_country_id)
                       VALUES (%s, %s, %s, %s, %s, %s, %s, %s)""",
                    (vin, mfr_id, model, year, fuel, engine_cc, steering, origin_cid)
                )

            # 3. Handle carnet (optional)
            carnet_id = None
            if carnet_number:
                existing_c = database.query(
                    "SELECT carnet_id FROM carnet WHERE carnet_number = %s",
                    (carnet_number,)
                )
                if existing_c:
                    carnet_id = existing_c[0]["carnet_id"]
                elif carnet_issue and carnet_expiry and carnet_cid:
                    carnet_id = database.execute(
                        """INSERT INTO carnet
                           (carnet_number, issuing_country_id, issue_date, expiry_date)
                           VALUES (%s, %s, %s, %s)""",
                        (carnet_number, carnet_cid, carnet_issue, carnet_expiry)
                    )

            # 4. Create the import application
            application_id = database.execute(
                """INSERT INTO import_application
                   (applicant_id, vehicle_id, carnet_id, import_type_id)
                   VALUES (%s, %s, %s, %s)""",
                (applicant_id, vehicle_id, carnet_id, import_type_id)
            )

            # 5. Record submitted documents
            for doc_id in doc_ids:
                database.execute(
                    """INSERT INTO submitted_document (application_id, document_id)
                       VALUES (%s, %s)""",
                    (application_id, doc_id)
                )

            # 6. Call the stored procedure (procedure does NOT commit itself)
            cursor = conn.cursor()
            cursor.callproc("CheckEligibility", (application_id,))
            while cursor.nextset():
                pass
            cursor.close()

            # 7. Commit the whole transaction
            conn.commit()

            return redirect(url_for("result", application_id=application_id))

        except mysql.connector.Error as e:
            conn.rollback()
            handle_db_error(e)
        except Exception as e:
            conn.rollback()
            flash(f"Unexpected error: {e}", "danger")

    return render_template(
        "check.html",
        manufacturers=manufacturers,
        countries=countries,
        import_types=import_types,
        documents=documents,
    )


@app.route("/result/<int:application_id>")
def result(application_id):
    """
    Show the latest eligibility result for an application.
    Displays a green PASSED / red FAILED badge plus per-rule breakdown.
    """
    # Get the application + applicant + vehicle details
    app_data = database.query(
        """
        SELECT ia.application_id, ia.application_date, ia.status,
               ap.full_name, ap.passport_number, ap.email,
               v.vin, v.model, v.manufacture_year, v.fuel_type,
               v.engine_cc, v.steering_side,
               m.name AS manufacturer,
               c.country_name AS origin_country,
               it.type_name AS import_type,
               cn.carnet_number, cn.expiry_date AS carnet_expiry
        FROM import_application ia
        JOIN applicant   ap ON ap.applicant_id   = ia.applicant_id
        JOIN vehicle     v  ON v.vehicle_id      = ia.vehicle_id
        JOIN manufacturer m  ON m.manufacturer_id = v.manufacturer_id
        JOIN country      c  ON c.country_id      = v.origin_country_id
        JOIN import_type  it ON it.import_type_id = ia.import_type_id
        LEFT JOIN carnet  cn ON cn.carnet_id      = ia.carnet_id
        WHERE ia.application_id = %s
        """,
        (application_id,)
    )
    if not app_data:
        flash("Application not found.", "danger")
        return redirect(url_for("index"))

    app_row = app_data[0]

    # Get the LATEST eligibility result
    result_row = database.query(
        """SELECT result_id, evaluation_date, overall_result, summary_reason
           FROM eligibility_result
           WHERE application_id = %s
           ORDER BY result_id DESC LIMIT 1""",
        (application_id,)
    )
    if not result_row:
        flash("No eligibility result found for this application.", "warning")
        return redirect(url_for("index"))

    result_data = result_row[0]

    # Get each rule's evaluation
    rule_evals = database.query(
        """SELECT re.outcome, re.actual_value, re.message,
                  er.rule_name, er.rule_type, er.operator, er.expected_value
           FROM rule_evaluation re
           JOIN eligibility_rule er ON er.rule_id = re.rule_id
           WHERE re.result_id = %s
           ORDER BY re.outcome DESC, er.rule_name""",
        (result_data["result_id"],)
    )

    return render_template(
        "result.html",
        app=app_row,
        result=result_data,
        rule_evals=rule_evals,
    )


@app.route("/rules")
def rules():
    """Public view of all active eligibility rules."""
    rows = database.query(
        """SELECT er.rule_id, er.rule_name, er.rule_type, er.operator,
                  er.expected_value, er.effective_date, er.last_updated,
                  er.description, it.type_name AS import_type
           FROM eligibility_rule er
           LEFT JOIN import_type it ON it.import_type_id = er.import_type_id
           WHERE er.is_active = 1
           ORDER BY er.rule_type, er.rule_name"""
    )
    return render_template("rules.html", rules=rows)


@app.route("/about")
def about():
    """About page with SQL concepts demonstrated."""
    return render_template("about.html")


# ==========================================================================
# ADMIN ROUTES
# ==========================================================================

@app.route("/admin/login", methods=["GET", "POST"])
def admin_login():
    if "admin_id" in session:
        return redirect(url_for("admin_dashboard"))

    if request.method == "POST":
        username = request.form.get("username", "").strip()
        password = request.form.get("password", "")

        rows = database.query(
            "SELECT admin_id, password_hash FROM admin_user WHERE username = %s",
            (username,)
        )
        if rows and check_password_hash(rows[0]["password_hash"], password):
            session["admin_id"] = rows[0]["admin_id"]
            session["admin_name"] = username
            flash("Logged in successfully.", "success")
            return redirect(url_for("admin_dashboard"))
        else:
            flash("Invalid username or password.", "danger")

    return render_template("admin/login.html")


@app.route("/admin/logout")
def admin_logout():
    session.clear()
    flash("Logged out.", "info")
    return redirect(url_for("admin_login"))


@app.route("/admin/dashboard")
@login_required
def admin_dashboard():
    """Dashboard with aggregate counts."""
    stats = database.query("""
        SELECT
            (SELECT COUNT(*) FROM import_application)                    AS total_apps,
            (SELECT COUNT(*) FROM import_application WHERE status='ELIGIBLE')  AS eligible,
            (SELECT COUNT(*) FROM import_application WHERE status='REJECTED')  AS rejected,
            (SELECT COUNT(*) FROM import_application WHERE status IN ('PENDING','UNDER_REVIEW')) AS pending,
            (SELECT COUNT(*) FROM carnet WHERE status='EXPIRED')          AS expired_carnets,
            (SELECT COUNT(*) FROM carnet WHERE status='ACTIVE' AND expiry_date BETWEEN CURDATE() AND DATE_ADD(CURDATE(), INTERVAL 30 DAY)) AS expiring_soon,
            (SELECT COUNT(*) FROM eligibility_rule WHERE is_active=1)    AS active_rules,
            (SELECT COUNT(*) FROM vehicle)                               AS total_vehicles,
            (SELECT COUNT(*) FROM applicant)                             AS total_applicants
    """)[0]
    recent_results = database.query("""
        SELECT er.result_id, er.evaluation_date, er.overall_result,
               ia.application_id, ap.full_name, v.model
        FROM eligibility_result er
        JOIN import_application ia ON ia.application_id = er.application_id
        JOIN applicant ap ON ap.applicant_id = ia.applicant_id
        JOIN vehicle   v  ON v.vehicle_id    = ia.vehicle_id
        ORDER BY er.result_id DESC LIMIT 8
    """)
    return render_template("admin/dashboard.html", stats=stats, recent_results=recent_results)


# ---- Helper: paginate list queries ----
def get_page():
    try:
        return max(1, int(request.args.get("page", 1)))
    except ValueError:
        return 1


# ==========================================================================
# ADMIN CRUD: VEHICLES
# ==========================================================================

@app.route("/admin/vehicles")
@login_required
def admin_vehicles():
    rows = database.query("""
        SELECT v.vehicle_id, v.vin, v.model, v.manufacture_year,
               v.fuel_type, v.engine_cc, v.steering_side,
               m.name AS manufacturer, c.country_name AS origin_country
        FROM vehicle v
        JOIN manufacturer m ON m.manufacturer_id = v.manufacturer_id
        JOIN country      c ON c.country_id       = v.origin_country_id
        ORDER BY v.vehicle_id DESC
    """)
    return render_template("admin/vehicles.html", vehicles=rows)


@app.route("/admin/vehicles/add", methods=["GET", "POST"])
@login_required
def admin_vehicle_add():
    manufacturers = database.query("SELECT manufacturer_id, name FROM manufacturer ORDER BY name")
    countries     = database.query("SELECT country_id, country_name FROM country ORDER BY country_name")
    if request.method == "POST":
        f = request.form
        try:
            conn = database.get_db()
            database.execute(
                """INSERT INTO vehicle
                   (vin, manufacturer_id, model, manufacture_year,
                    fuel_type, engine_cc, steering_side, origin_country_id)
                   VALUES (%s,%s,%s,%s,%s,%s,%s,%s)""",
                (f["vin"].strip().upper(), f["manufacturer_id"], f["model"].strip(),
                 f["manufacture_year"], f["fuel_type"], f.get("engine_cc") or 0,
                 f["steering_side"], f["origin_country_id"])
            )
            conn.commit()
            flash("Vehicle added.", "success")
            return redirect(url_for("admin_vehicles"))
        except mysql.connector.Error as e:
            conn.rollback()
            handle_db_error(e)
    return render_template("admin/vehicle_form.html",
                           manufacturers=manufacturers, countries=countries,
                           vehicle=None, action="Add")


@app.route("/admin/vehicles/edit/<int:vid>", methods=["GET", "POST"])
@login_required
def admin_vehicle_edit(vid):
    manufacturers = database.query("SELECT manufacturer_id, name FROM manufacturer ORDER BY name")
    countries     = database.query("SELECT country_id, country_name FROM country ORDER BY country_name")
    vehicle       = crud_get("SELECT * FROM vehicle WHERE vehicle_id=%s", (vid,))
    if not vehicle:
        flash("Vehicle not found.", "danger")
        return redirect(url_for("admin_vehicles"))
    if request.method == "POST":
        f = request.form
        try:
            conn = database.get_db()
            database.execute(
                """UPDATE vehicle SET vin=%s, manufacturer_id=%s, model=%s,
                   manufacture_year=%s, fuel_type=%s, engine_cc=%s,
                   steering_side=%s, origin_country_id=%s
                   WHERE vehicle_id=%s""",
                (f["vin"].strip().upper(), f["manufacturer_id"], f["model"].strip(),
                 f["manufacture_year"], f["fuel_type"], f.get("engine_cc") or 0,
                 f["steering_side"], f["origin_country_id"], vid)
            )
            conn.commit()
            flash("Vehicle updated.", "success")
            return redirect(url_for("admin_vehicles"))
        except mysql.connector.Error as e:
            conn.rollback()
            handle_db_error(e)
    return render_template("admin/vehicle_form.html",
                           manufacturers=manufacturers, countries=countries,
                           vehicle=vehicle, action="Edit")


@app.route("/admin/vehicles/delete/<int:vid>", methods=["POST"])
@login_required
def admin_vehicle_delete(vid):
    try:
        conn = database.get_db()
        crud_delete("vehicle", "vehicle_id", vid)
        conn.commit()
        flash("Vehicle deleted.", "success")
    except mysql.connector.Error as e:
        conn.rollback()
        handle_db_error(e)
    return redirect(url_for("admin_vehicles"))


# ==========================================================================
# ADMIN CRUD: MANUFACTURERS
# ==========================================================================

@app.route("/admin/manufacturers")
@login_required
def admin_manufacturers():
    rows = database.query("""
        SELECT m.manufacturer_id, m.name, c.country_name
        FROM manufacturer m JOIN country c ON c.country_id=m.country_id
        ORDER BY m.name
    """)
    return render_template("admin/manufacturers.html", manufacturers=rows)


@app.route("/admin/manufacturers/add", methods=["GET", "POST"])
@login_required
def admin_manufacturer_add():
    countries = database.query("SELECT country_id, country_name FROM country ORDER BY country_name")
    if request.method == "POST":
        f = request.form
        try:
            conn = database.get_db()
            database.execute("INSERT INTO manufacturer(name,country_id) VALUES(%s,%s)",
                             (f["name"].strip(), f["country_id"]))
            conn.commit()
            flash("Manufacturer added.", "success")
            return redirect(url_for("admin_manufacturers"))
        except mysql.connector.Error as e:
            conn.rollback()
            handle_db_error(e)
    return render_template("admin/manufacturer_form.html", countries=countries,
                           manufacturer=None, action="Add")


@app.route("/admin/manufacturers/edit/<int:mid>", methods=["GET", "POST"])
@login_required
def admin_manufacturer_edit(mid):
    countries    = database.query("SELECT country_id, country_name FROM country ORDER BY country_name")
    manufacturer = crud_get("SELECT * FROM manufacturer WHERE manufacturer_id=%s", (mid,))
    if not manufacturer:
        flash("Manufacturer not found.", "danger")
        return redirect(url_for("admin_manufacturers"))
    if request.method == "POST":
        f = request.form
        try:
            conn = database.get_db()
            database.execute("UPDATE manufacturer SET name=%s, country_id=%s WHERE manufacturer_id=%s",
                             (f["name"].strip(), f["country_id"], mid))
            conn.commit()
            flash("Manufacturer updated.", "success")
            return redirect(url_for("admin_manufacturers"))
        except mysql.connector.Error as e:
            conn.rollback()
            handle_db_error(e)
    return render_template("admin/manufacturer_form.html", countries=countries,
                           manufacturer=manufacturer, action="Edit")


@app.route("/admin/manufacturers/delete/<int:mid>", methods=["POST"])
@login_required
def admin_manufacturer_delete(mid):
    try:
        conn = database.get_db()
        crud_delete("manufacturer", "manufacturer_id", mid)
        conn.commit()
        flash("Manufacturer deleted.", "success")
    except mysql.connector.Error as e:
        conn.rollback()
        handle_db_error(e)
    return redirect(url_for("admin_manufacturers"))


# ==========================================================================
# ADMIN CRUD: COUNTRIES
# ==========================================================================

@app.route("/admin/countries")
@login_required
def admin_countries():
    rows = database.query("SELECT * FROM country ORDER BY country_name")
    return render_template("admin/countries.html", countries=rows)


@app.route("/admin/countries/add", methods=["GET", "POST"])
@login_required
def admin_country_add():
    if request.method == "POST":
        f = request.form
        try:
            conn = database.get_db()
            database.execute(
                "INSERT INTO country(country_name,driving_side,is_carnet_member) VALUES(%s,%s,%s)",
                (f["country_name"].strip(), f["driving_side"],
                 1 if f.get("is_carnet_member") else 0)
            )
            conn.commit()
            flash("Country added.", "success")
            return redirect(url_for("admin_countries"))
        except mysql.connector.Error as e:
            conn.rollback()
            handle_db_error(e)
    return render_template("admin/country_form.html", country=None, action="Add")


@app.route("/admin/countries/edit/<int:cid>", methods=["GET", "POST"])
@login_required
def admin_country_edit(cid):
    country = crud_get("SELECT * FROM country WHERE country_id=%s", (cid,))
    if not country:
        flash("Country not found.", "danger")
        return redirect(url_for("admin_countries"))
    if request.method == "POST":
        f = request.form
        try:
            conn = database.get_db()
            database.execute(
                "UPDATE country SET country_name=%s,driving_side=%s,is_carnet_member=%s WHERE country_id=%s",
                (f["country_name"].strip(), f["driving_side"],
                 1 if f.get("is_carnet_member") else 0, cid)
            )
            conn.commit()
            flash("Country updated.", "success")
            return redirect(url_for("admin_countries"))
        except mysql.connector.Error as e:
            conn.rollback()
            handle_db_error(e)
    return render_template("admin/country_form.html", country=country, action="Edit")


@app.route("/admin/countries/delete/<int:cid>", methods=["POST"])
@login_required
def admin_country_delete(cid):
    try:
        conn = database.get_db()
        crud_delete("country", "country_id", cid)
        conn.commit()
        flash("Country deleted.", "success")
    except mysql.connector.Error as e:
        conn.rollback()
        handle_db_error(e)
    return redirect(url_for("admin_countries"))


# ==========================================================================
# ADMIN CRUD: APPLICANTS
# ==========================================================================

@app.route("/admin/applicants")
@login_required
def admin_applicants():
    rows = database.query("SELECT * FROM applicant ORDER BY full_name")
    return render_template("admin/applicants.html", applicants=rows)


@app.route("/admin/applicants/add", methods=["GET", "POST"])
@login_required
def admin_applicant_add():
    if request.method == "POST":
        f = request.form
        try:
            conn = database.get_db()
            database.execute(
                "INSERT INTO applicant(full_name,passport_number,phone,email,address) VALUES(%s,%s,%s,%s,%s)",
                (f["full_name"].strip(), f["passport_number"].strip(),
                 f.get("phone","").strip(), f.get("email","").strip(), f.get("address","").strip())
            )
            conn.commit()
            flash("Applicant added.", "success")
            return redirect(url_for("admin_applicants"))
        except mysql.connector.Error as e:
            conn.rollback()
            handle_db_error(e)
    return render_template("admin/applicant_form.html", applicant=None, action="Add")


@app.route("/admin/applicants/edit/<int:aid>", methods=["GET", "POST"])
@login_required
def admin_applicant_edit(aid):
    applicant = crud_get("SELECT * FROM applicant WHERE applicant_id=%s", (aid,))
    if not applicant:
        flash("Applicant not found.", "danger")
        return redirect(url_for("admin_applicants"))
    if request.method == "POST":
        f = request.form
        try:
            conn = database.get_db()
            database.execute(
                "UPDATE applicant SET full_name=%s,passport_number=%s,phone=%s,email=%s,address=%s WHERE applicant_id=%s",
                (f["full_name"].strip(), f["passport_number"].strip(),
                 f.get("phone","").strip(), f.get("email","").strip(),
                 f.get("address","").strip(), aid)
            )
            conn.commit()
            flash("Applicant updated.", "success")
            return redirect(url_for("admin_applicants"))
        except mysql.connector.Error as e:
            conn.rollback()
            handle_db_error(e)
    return render_template("admin/applicant_form.html", applicant=applicant, action="Edit")


@app.route("/admin/applicants/delete/<int:aid>", methods=["POST"])
@login_required
def admin_applicant_delete(aid):
    try:
        conn = database.get_db()
        crud_delete("applicant", "applicant_id", aid)
        conn.commit()
        flash("Applicant deleted.", "success")
    except mysql.connector.Error as e:
        conn.rollback()
        handle_db_error(e)
    return redirect(url_for("admin_applicants"))


# ==========================================================================
# ADMIN CRUD: CARNETS
# ==========================================================================

@app.route("/admin/carnets")
@login_required
def admin_carnets():
    rows = database.query("""
        SELECT cn.*, c.country_name AS issuing_country
        FROM carnet cn JOIN country c ON c.country_id=cn.issuing_country_id
        ORDER BY cn.carnet_id DESC
    """)
    return render_template("admin/carnets.html", carnets=rows)


@app.route("/admin/carnets/add", methods=["GET", "POST"])
@login_required
def admin_carnet_add():
    countries = database.query("SELECT country_id, country_name FROM country ORDER BY country_name")
    if request.method == "POST":
        f = request.form
        try:
            conn = database.get_db()
            database.execute(
                "INSERT INTO carnet(carnet_number,issuing_country_id,issue_date,expiry_date) VALUES(%s,%s,%s,%s)",
                (f["carnet_number"].strip(), f["issuing_country_id"],
                 f["issue_date"], f["expiry_date"])
            )
            conn.commit()
            flash("Carnet added.", "success")
            return redirect(url_for("admin_carnets"))
        except mysql.connector.Error as e:
            conn.rollback()
            handle_db_error(e)
    return render_template("admin/carnet_form.html", countries=countries, carnet=None, action="Add")


@app.route("/admin/carnets/edit/<int:cid>", methods=["GET", "POST"])
@login_required
def admin_carnet_edit(cid):
    countries = database.query("SELECT country_id, country_name FROM country ORDER BY country_name")
    carnet    = crud_get("SELECT * FROM carnet WHERE carnet_id=%s", (cid,))
    if not carnet:
        flash("Carnet not found.", "danger")
        return redirect(url_for("admin_carnets"))
    if request.method == "POST":
        f = request.form
        try:
            conn = database.get_db()
            database.execute(
                "UPDATE carnet SET carnet_number=%s,issuing_country_id=%s,issue_date=%s,expiry_date=%s,status=%s WHERE carnet_id=%s",
                (f["carnet_number"].strip(), f["issuing_country_id"],
                 f["issue_date"], f["expiry_date"], f["status"], cid)
            )
            conn.commit()
            flash("Carnet updated.", "success")
            return redirect(url_for("admin_carnets"))
        except mysql.connector.Error as e:
            conn.rollback()
            handle_db_error(e)
    return render_template("admin/carnet_form.html", countries=countries, carnet=carnet, action="Edit")


@app.route("/admin/carnets/delete/<int:cid>", methods=["POST"])
@login_required
def admin_carnet_delete(cid):
    try:
        conn = database.get_db()
        crud_delete("carnet", "carnet_id", cid)
        conn.commit()
        flash("Carnet deleted.", "success")
    except mysql.connector.Error as e:
        conn.rollback()
        handle_db_error(e)
    return redirect(url_for("admin_carnets"))


# ==========================================================================
# ADMIN CRUD: APPLICATIONS
# ==========================================================================

@app.route("/admin/applications")
@login_required
def admin_applications():
    rows = database.query("""
        SELECT ia.application_id, ia.application_date, ia.status,
               ap.full_name, v.model, it.type_name
        FROM import_application ia
        JOIN applicant   ap ON ap.applicant_id   = ia.applicant_id
        JOIN vehicle     v  ON v.vehicle_id      = ia.vehicle_id
        JOIN import_type it ON it.import_type_id = ia.import_type_id
        ORDER BY ia.application_id DESC
    """)
    return render_template("admin/applications.html", applications=rows)


@app.route("/admin/applications/rerun/<int:app_id>", methods=["POST"])
@login_required
def admin_application_rerun(app_id):
    """Re-run CheckEligibility for an existing application."""
    conn = database.get_db()
    try:
        cursor = conn.cursor()
        cursor.callproc("CheckEligibility", (app_id,))
        while cursor.nextset():
            pass
        cursor.close()
        conn.commit()
        flash(f"Eligibility re-evaluated for application #{app_id}.", "success")
    except mysql.connector.Error as e:
        conn.rollback()
        handle_db_error(e)
    return redirect(url_for("admin_applications"))


@app.route("/admin/applications/delete/<int:app_id>", methods=["POST"])
@login_required
def admin_application_delete(app_id):
    try:
        conn = database.get_db()
        crud_delete("import_application", "application_id", app_id)
        conn.commit()
        flash("Application deleted.", "success")
    except mysql.connector.Error as e:
        conn.rollback()
        handle_db_error(e)
    return redirect(url_for("admin_applications"))


# ==========================================================================
# ADMIN CRUD: DOCUMENTS
# ==========================================================================

@app.route("/admin/documents")
@login_required
def admin_documents():
    rows = database.query("SELECT * FROM document ORDER BY document_name")
    return render_template("admin/documents.html", documents=rows)


@app.route("/admin/documents/add", methods=["GET", "POST"])
@login_required
def admin_document_add():
    if request.method == "POST":
        f = request.form
        try:
            conn = database.get_db()
            database.execute(
                "INSERT INTO document(document_name,is_mandatory) VALUES(%s,%s)",
                (f["document_name"].strip(), 1 if f.get("is_mandatory") else 0)
            )
            conn.commit()
            flash("Document added.", "success")
            return redirect(url_for("admin_documents"))
        except mysql.connector.Error as e:
            conn.rollback()
            handle_db_error(e)
    return render_template("admin/document_form.html", document=None, action="Add")


@app.route("/admin/documents/edit/<int:did>", methods=["GET", "POST"])
@login_required
def admin_document_edit(did):
    document = crud_get("SELECT * FROM document WHERE document_id=%s", (did,))
    if not document:
        flash("Document not found.", "danger")
        return redirect(url_for("admin_documents"))
    if request.method == "POST":
        f = request.form
        try:
            conn = database.get_db()
            database.execute(
                "UPDATE document SET document_name=%s, is_mandatory=%s WHERE document_id=%s",
                (f["document_name"].strip(), 1 if f.get("is_mandatory") else 0, did)
            )
            conn.commit()
            flash("Document updated.", "success")
            return redirect(url_for("admin_documents"))
        except mysql.connector.Error as e:
            conn.rollback()
            handle_db_error(e)
    return render_template("admin/document_form.html", document=document, action="Edit")


@app.route("/admin/documents/delete/<int:did>", methods=["POST"])
@login_required
def admin_document_delete(did):
    try:
        conn = database.get_db()
        crud_delete("document", "document_id", did)
        conn.commit()
        flash("Document deleted.", "success")
    except mysql.connector.Error as e:
        conn.rollback()
        handle_db_error(e)
    return redirect(url_for("admin_documents"))


# ==========================================================================
# ADMIN CRUD: ELIGIBILITY RULES
# ==========================================================================

@app.route("/admin/rules")
@login_required
def admin_rules():
    rows = database.query("""
        SELECT er.*, it.type_name
        FROM eligibility_rule er
        LEFT JOIN import_type it ON it.import_type_id = er.import_type_id
        ORDER BY er.is_active DESC, er.rule_name
    """)
    return render_template("admin/rules.html", rules=rows)


@app.route("/admin/rules/add", methods=["GET", "POST"])
@login_required
def admin_rule_add():
    import_types = database.query("SELECT * FROM import_type ORDER BY type_name")
    if request.method == "POST":
        f = request.form
        try:
            conn = database.get_db()
            database.execute(
                """INSERT INTO eligibility_rule
                   (rule_name,rule_type,operator,expected_value,import_type_id,
                    is_active,effective_date,description)
                   VALUES(%s,%s,%s,%s,%s,%s,%s,%s)""",
                (f["rule_name"].strip(), f["rule_type"], f["operator"],
                 f["expected_value"].strip(),
                 f["import_type_id"] if f.get("import_type_id") else None,
                 1 if f.get("is_active") else 0,
                 f["effective_date"], f.get("description","").strip())
            )
            conn.commit()
            flash("Rule added.", "success")
            return redirect(url_for("admin_rules"))
        except mysql.connector.Error as e:
            conn.rollback()
            handle_db_error(e)
    return render_template("admin/rule_form.html", import_types=import_types,
                           rule=None, action="Add")


@app.route("/admin/rules/edit/<int:rid>", methods=["GET", "POST"])
@login_required
def admin_rule_edit(rid):
    import_types = database.query("SELECT * FROM import_type ORDER BY type_name")
    rule         = crud_get("SELECT * FROM eligibility_rule WHERE rule_id=%s", (rid,))
    if not rule:
        flash("Rule not found.", "danger")
        return redirect(url_for("admin_rules"))
    if request.method == "POST":
        f = request.form
        try:
            conn = database.get_db()
            database.execute(
                """UPDATE eligibility_rule
                   SET rule_name=%s,rule_type=%s,operator=%s,expected_value=%s,
                       import_type_id=%s,is_active=%s,effective_date=%s,description=%s
                   WHERE rule_id=%s""",
                (f["rule_name"].strip(), f["rule_type"], f["operator"],
                 f["expected_value"].strip(),
                 f["import_type_id"] if f.get("import_type_id") else None,
                 1 if f.get("is_active") else 0,
                 f["effective_date"], f.get("description","").strip(), rid)
            )
            conn.commit()
            flash("Rule updated.", "success")
            return redirect(url_for("admin_rules"))
        except mysql.connector.Error as e:
            conn.rollback()
            handle_db_error(e)
    return render_template("admin/rule_form.html", import_types=import_types,
                           rule=rule, action="Edit")


@app.route("/admin/rules/toggle/<int:rid>", methods=["POST"])
@login_required
def admin_rule_toggle(rid):
    """Toggle a rule's active/inactive status."""
    conn = database.get_db()
    try:
        database.execute(
            "UPDATE eligibility_rule SET is_active = NOT is_active WHERE rule_id=%s",
            (rid,)
        )
        conn.commit()
        flash("Rule status toggled.", "success")
    except mysql.connector.Error as e:
        conn.rollback()
        handle_db_error(e)
    return redirect(url_for("admin_rules"))


@app.route("/admin/rules/delete/<int:rid>", methods=["POST"])
@login_required
def admin_rule_delete(rid):
    try:
        conn = database.get_db()
        crud_delete("eligibility_rule", "rule_id", rid)
        conn.commit()
        flash("Rule deleted.", "success")
    except mysql.connector.Error as e:
        conn.rollback()
        handle_db_error(e)
    return redirect(url_for("admin_rules"))


# ==========================================================================
# ADMIN: RESULTS + DRILL-DOWN
# ==========================================================================

@app.route("/admin/results")
@login_required
def admin_results():
    rows = database.query("""
        SELECT er.result_id, er.evaluation_date, er.overall_result,
               er.summary_reason,
               ia.application_id, ap.full_name, v.model
        FROM eligibility_result er
        JOIN import_application ia ON ia.application_id = er.application_id
        JOIN applicant ap ON ap.applicant_id = ia.applicant_id
        JOIN vehicle   v  ON v.vehicle_id    = ia.vehicle_id
        ORDER BY er.result_id DESC
    """)
    return render_template("admin/results.html", results=rows)


@app.route("/admin/results/<int:result_id>")
@login_required
def admin_result_detail(result_id):
    result_row = crud_get(
        """SELECT er.*, ia.application_id, ap.full_name, v.model
           FROM eligibility_result er
           JOIN import_application ia ON ia.application_id=er.application_id
           JOIN applicant ap ON ap.applicant_id=ia.applicant_id
           JOIN vehicle   v  ON v.vehicle_id=ia.vehicle_id
           WHERE er.result_id=%s""",
        (result_id,)
    )
    if not result_row:
        flash("Result not found.", "danger")
        return redirect(url_for("admin_results"))
    evals = database.query(
        """SELECT re.*, er.rule_name, er.rule_type
           FROM rule_evaluation re
           JOIN eligibility_rule er ON er.rule_id=re.rule_id
           WHERE re.result_id=%s ORDER BY re.outcome DESC, er.rule_name""",
        (result_id,)
    )
    return render_template("admin/result_detail.html", result=result_row, evals=evals)


# ==========================================================================
# ADMIN: REPORTS
# ==========================================================================

@app.route("/admin/reports")
@login_required
def admin_reports():
    # JOIN report
    join_data = database.query("""
        SELECT ia.application_id, ia.application_date, ia.status,
               ap.full_name AS applicant, ap.passport_number,
               v.vin, v.model, v.manufacture_year,
               m.name AS manufacturer,
               c.country_name AS origin_country,
               it.type_name AS import_type
        FROM import_application ia
        JOIN applicant   ap ON ap.applicant_id   = ia.applicant_id
        JOIN vehicle     v  ON v.vehicle_id      = ia.vehicle_id
        JOIN manufacturer m  ON m.manufacturer_id = v.manufacturer_id
        JOIN country      c  ON c.country_id      = v.origin_country_id
        JOIN import_type  it ON it.import_type_id = ia.import_type_id
        ORDER BY ia.application_id
    """)

    # GROUP BY / HAVING report
    groupby_data = database.query("""
        SELECT c.country_name,
               COUNT(ia.application_id) AS total_applications
        FROM import_application ia
        JOIN vehicle v ON v.vehicle_id=ia.vehicle_id
        JOIN country c ON c.country_id=v.origin_country_id
        GROUP BY c.country_id, c.country_name
        ORDER BY total_applications DESC
    """)

    # SUBQUERY report
    subquery_data = database.query("""
        SELECT v.vehicle_id, v.vin, v.model, v.manufacture_year,
               m.name AS manufacturer,
               (YEAR(CURDATE())-v.manufacture_year) AS age_years
        FROM vehicle v JOIN manufacturer m ON m.manufacturer_id=v.manufacturer_id
        WHERE v.manufacture_year < (SELECT AVG(manufacture_year) FROM vehicle)
        ORDER BY v.manufacture_year
    """)

    # EXISTS report
    exists_data = database.query("""
        SELECT ia.application_id, ap.full_name AS applicant,
               ia.status, it.type_name AS import_type
        FROM import_application ia
        JOIN applicant   ap ON ap.applicant_id   = ia.applicant_id
        JOIN import_type it ON it.import_type_id = ia.import_type_id
        WHERE NOT EXISTS (
            SELECT 1 FROM document d
            WHERE d.is_mandatory=TRUE
              AND NOT EXISTS (
                  SELECT 1 FROM submitted_document sd
                  WHERE sd.application_id=ia.application_id
                    AND sd.document_id=d.document_id
              )
        )
        ORDER BY ia.application_id
    """)

    # CASE report
    case_data = database.query("""
        SELECT ia.application_id, v.model, v.manufacture_year,
               (YEAR(CURDATE())-v.manufacture_year) AS age_years,
               CASE WHEN (YEAR(CURDATE())-v.manufacture_year)<=3 THEN 'NEW'
                    WHEN (YEAR(CURDATE())-v.manufacture_year)<=7 THEN 'MID'
                    ELSE 'OLD' END AS age_category,
               CASE ia.status
                    WHEN 'ELIGIBLE'  THEN 'Approved for Import'
                    WHEN 'REJECTED'  THEN 'Rejected'
                    WHEN 'PENDING'   THEN 'Awaiting Review'
                    WHEN 'UNDER_REVIEW' THEN 'Under Review'
                    ELSE ia.status END AS status_label
        FROM import_application ia JOIN vehicle v ON v.vehicle_id=ia.vehicle_id
        ORDER BY age_years
    """)

    # Most failed rules
    failed_rules = database.query("""
        SELECT er.rule_name, er.rule_type, COUNT(re.evaluation_id) AS fail_count
        FROM eligibility_rule er
        JOIN rule_evaluation re ON re.rule_id=er.rule_id
        WHERE re.outcome='FAIL'
        GROUP BY er.rule_id, er.rule_name, er.rule_type
        ORDER BY fail_count DESC LIMIT 10
    """)

    # By manufacturer
    by_manufacturer = database.query("""
        SELECT m.name AS manufacturer,
               COUNT(ia.application_id) AS applications,
               SUM(ia.status='ELIGIBLE') AS eligible,
               SUM(ia.status='REJECTED') AS rejected
        FROM import_application ia
        JOIN vehicle      v ON v.vehicle_id=ia.vehicle_id
        JOIN manufacturer m ON m.manufacturer_id=v.manufacturer_id
        GROUP BY m.manufacturer_id, m.name
        ORDER BY applications DESC
    """)

    # By import type
    by_type = database.query("""
        SELECT it.type_name,
               COUNT(ia.application_id) AS total,
               SUM(ia.status='ELIGIBLE') AS eligible,
               SUM(ia.status='REJECTED') AS rejected,
               SUM(ia.status IN ('PENDING','UNDER_REVIEW')) AS pending
        FROM import_application ia
        JOIN import_type it ON it.import_type_id=ia.import_type_id
        GROUP BY it.import_type_id, it.type_name
    """)

    # Expired carnets
    expired_carnets = database.query("""
        SELECT cn.carnet_number, cn.expiry_date, c.country_name AS issuing_country
        FROM carnet cn JOIN country c ON c.country_id=cn.issuing_country_id
        WHERE cn.status='EXPIRED' ORDER BY cn.expiry_date DESC
    """)

    # Expiring soon (from view)
    expiring_soon = database.query("SELECT * FROM v_carnets_expiring_soon ORDER BY days_left")

    # Missing documents (from view)
    missing_docs = database.query("SELECT * FROM v_applications_missing_documents")

    return render_template("admin/reports.html",
        join_data=join_data,
        groupby_data=groupby_data,
        subquery_data=subquery_data,
        exists_data=exists_data,
        case_data=case_data,
        failed_rules=failed_rules,
        by_manufacturer=by_manufacturer,
        by_type=by_type,
        expired_carnets=expired_carnets,
        expiring_soon=expiring_soon,
        missing_docs=missing_docs,
    )


# ==========================================================================
# ADMIN: AUDIT LOG VIEW
# ==========================================================================

@app.route("/admin/auditlog")
@login_required
def admin_auditlog():
    rows = database.query("""
        SELECT ral.*, er.rule_name
        FROM rule_audit_log ral
        LEFT JOIN eligibility_rule er ON er.rule_id=ral.rule_id
        ORDER BY ral.log_id DESC LIMIT 100
    """)
    return render_template("admin/auditlog.html", logs=rows)


# ==========================================================================
# RUN
# ==========================================================================

if __name__ == "__main__":
    app.run(debug=True, port=5000)

