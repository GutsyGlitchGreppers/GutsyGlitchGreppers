// toggle toc -> header.html -> .span_right .popup_btn
function toggle_toc() {
    document.getElementById("popup_toc").classList.toggle("show");
}

// open collection list -> header.html -> .collection_list
function open_collection_list() {
    document.getElementById("the_collection_list").classList.add("show");
    show_collection("all");
}
// close collection list -> collections.html -> .collection_list
function close_collection_list() {
    document.getElementById("the_collection_list").classList.remove("show");
    var collection_labels = document.getElementsByClassName("post_list_in_1_collection");
    for (idx = 0; idx < collection_labels.length; idx++) {
        collection_labels[idx].classList.remove("show");
    }
}

// toggle  -> collections.html -> .post_list
function show_collection(col_name) {
    var collection_labels = document.getElementsByClassName("post_list_in_1_collection");
    for (idx = 0; idx < collection_labels.length; idx++) {
        collection_labels[idx].classList.remove("show");
    }
    document.getElementById(col_name).classList.add("show");
    document.getElementById("clh_title").innerHTML = col_name;
}

//scroll page -> header.html -> .span_right prev & next btn
function scroll_percentage(mtpler) {
    document
        .getElementById("div_atcl")
        .scrollBy(0, window.innerHeight * mtpler);
}

var maximize_storage_key = "ggg:maximized";

function read_maximize_preference() {
    try {
        return window.localStorage.getItem(maximize_storage_key) === "true";
    } catch (e) {
        return false;
    }
}

function write_maximize_preference(is_maximized) {
    try {
        window.localStorage.setItem(maximize_storage_key, String(is_maximized));
    } catch (e) {
        return;
    }
}

function sync_maximize_root_class(is_maximized) {
    document.documentElement.classList.toggle("persist-maximized", is_maximized);
}

function set_maximize_state(is_maximized, persist_preference) {
    if (typeof ctner === "undefined" || !ctner) {
        return;
    }

    ctner.style.top = "0";
    ctner.style.height = "100vh";
    ctner.style.minHeight = "100vh";

    if (is_maximized) {
        ctner.style.width = "100%";
        ctner.style.maxWidth = "100%";
        ctner.classList.add("is-maximized");
    } else {
        ctner.style.width = "84%";
        ctner.style.maxWidth = "1350px";
        ctner.classList.remove("is-maximized");
    }

    if (document.getElementById("mxmz_text")) {
        document.getElementById("mxmz_text").innerHTML = is_maximized
            ? "Restore"
            : "Maximize";
    }

    ctner_state = is_maximized ? 1 : 0;
    sync_maximize_root_class(is_maximized);

    if (persist_preference !== false) {
        write_maximize_preference(is_maximized);
    }
}

function initialize_maximize_state() {
    set_maximize_state(read_maximize_preference(), false);
}

// toggle entire page -> header.html -> #mxmz_btn
function toggle_maximize() {
    set_maximize_state(ctner_state === 0);
}

// Decrypt secret message -> header.html -> #asc_btn
function apply_token() {
    // perform decryption
    function decrypt_all(pwd, class_name) {
        var elem_clct = document.getElementsByClassName(class_name);
        if (elem_clct.length == 0) {
            console.log("No texts to decrypt!");
            return false;
        }
        for (acc = 0; acc < elem_clct.length; acc++) {
            var encrypted = elem_clct[acc].id;
            var ct =
                '{"iv":"' +
                encrypted.substring(0, 22) +
                '==",salt:"","ct":"' +
                encrypted.substring(22) +
                '"}';
            try {
                var txt = sjcl.json.decrypt(pwd, ct);
            } catch (e) {
                alert("Invalid Access Token!");
                return;
            }
            elem_clct[acc].innerHTML = txt;
        }
        return true;
    }
    // do html stuff then apply DECRYPT_ALL
    var tkn = document.getElementById("acs_tkn");
    if (decrypt_all(tkn.value, "encrypted")) {
        tkn.style.display = "none";
        document.getElementById("acs_btn").style.display = "none";
    }
}
