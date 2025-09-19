#!/bin/sh
# nginx_cp_upload.sh - patch/unpatch nginx.conf for Creality Print uploads
# BusyBox-safe, no temp files: awk to find line numbers, sed -i for in-place edits.

NGINX_CONF="/etc/nginx/nginx.conf"

# ---------- Find insertion points (line numbers) ----------

server_close_line() {
  # Closing brace of the single server{} block:
  # track the last '}' seen BEFORE the 'map $http_upgrade' line.
  awk '
    BEGIN{lastclose=0}
    /^[ \t]*}$/ { lastclose=NR }
    /^[ \t]*map[ \t]+\$http_upgrade[ \t]/ { print lastclose; exit }
  ' "$NGINX_CONF"
}

http_close_line() {
  # Closing brace of the http{} block: last '}' in the file.
  awk '
    /^[ \t]*}$/ { last=NR }
    END { if (last>0) print last }
  ' "$NGINX_CONF"
}

already_patched() {
  grep -q 'CP_UPLOAD_LOC_BEGIN\|CP_UPLOAD_UP_BEGIN' "$NGINX_CONF"
}

# ---------- Pure in-place patch helpers ----------

insert_location_block() {
  L="$(server_close_line)"
  [ -z "$L" ] && { echo "ERROR: cannot find server{} closing brace."; return 1; }
  grep -q 'location ^~ /upload/' "$NGINX_CONF" && { echo "Location block already present, skipping."; return 0; }

  # Insert BEFORE line $L, in REVERSE order so the final order is correct.
  # Final result inside server{}:
  #   (blank line)
  #   # >>> CP_UPLOAD_LOC_BEGIN
  #   location ^~ /upload/ { ... }
  #   # <<< CP_UPLOAD_LOC_END
  #   }
  sed -i "${L}i\        # <<< CP_UPLOAD_LOC_END"            "$NGINX_CONF"
  sed -i "${L}i\        }"                                  "$NGINX_CONF"
  sed -i "${L}i\            proxy_read_timeout 300s;"       "$NGINX_CONF"
  sed -i "${L}i\            proxy_send_timeout 300s;"       "$NGINX_CONF"
  sed -i "${L}i\            proxy_connect_timeout 300s;"    "$NGINX_CONF"
  sed -i "${L}i\            proxy_buffering off;"           "$NGINX_CONF"
  sed -i "${L}i\            proxy_request_buffering off;"   "$NGINX_CONF"
  sed -i "${L}i\            proxy_pass http://api_files_shim;" "$NGINX_CONF"
  sed -i "${L}i\        location ^~ /upload/ {"             "$NGINX_CONF"
  sed -i "${L}i\        # >>> CP_UPLOAD_LOC_BEGIN"          "$NGINX_CONF"
  sed -i "${L}i\\"                                           "$NGINX_CONF"  # one blank line before marker
}

insert_upstream_block() {
  H="$(http_close_line)"
  [ -z "$H" ] && { echo "ERROR: cannot find http{} closing brace."; return 1; }
  grep -q 'upstream api_files_shim' "$NGINX_CONF" && { echo "Upstream block already present, skipping."; return 0; }

  # Insert BEFORE http{} closing '}', in REVERSE order.
  # Final result near end of http{}:
  #   (blank line)
  #   # >>> CP_UPLOAD_UP_BEGIN
  #   upstream api_files_shim { server 127.0.0.1:8090; }
  #   # <<< CP_UPLOAD_UP_END
  # }
  sed -i "${H}i\    # <<< CP_UPLOAD_UP_END"           "$NGINX_CONF"
  sed -i "${H}i\    }"                                "$NGINX_CONF"
  sed -i "${H}i\        server 127.0.0.1:8090;"       "$NGINX_CONF"
  sed -i "${H}i\    upstream api_files_shim {"        "$NGINX_CONF"
  sed -i "${H}i\    # >>> CP_UPLOAD_UP_BEGIN"         "$NGINX_CONF"
  sed -i "${H}i\\"                                     "$NGINX_CONF"  # one blank line before upstream marker
}

tidy_whitespace_end() {
  # Collapse 3+ blank lines to 2 (global)
  sed -i ':a;N;$!ba;s/\n\{3,\}/\n\n/g' "$NGINX_CONF"
  # Remove a single blank line that sits directly before ANY closing brace, preserving indentation:
  # (turn "\n[spaces]\n[spaces]}" into "\n[spaces]}")
  sed -i ':a;N;$!ba;s/\n[ \t]*\n\([ \t]*}\)/\n\1/g' "$NGINX_CONF"
}

# ---------- Patch / Unpatch / Status ----------

patch_nginx() {
  echo ">>> Patching nginx.conf..."
  if already_patched; then
    echo "Already patched."
    return 0
  fi

  insert_location_block || { echo "Patch failed while inserting location."; return 1; }
  insert_upstream_block || { echo "Patch failed while inserting upstream."; return 1; }

  if nginx -t; then
    echo "Patch successful, reloading nginx..."
    nginx -s reload
  else
    echo "Patch failed validation, reverting..."
    unpatch_nginx
    return 1
  fi
}

unpatch_nginx() {
  echo ">>> Unpatching nginx.conf..."
  if ! already_patched; then
    echo "Nothing to unpatch (markers not found)."
    return 0
  fi

  # Remove location and upstream marker blocks
  sed -i '/# >>> CP_UPLOAD_LOC_BEGIN/,/# <<< CP_UPLOAD_LOC_END/d' "$NGINX_CONF"
  sed -i '/# >>> CP_UPLOAD_UP_BEGIN/,/# <<< CP_UPLOAD_UP_END/d'   "$NGINX_CONF"

  # Normalize whitespace so there is NO blank line left before server's '}' and none before final http '}'
  tidy_whitespace_end

  if nginx -t; then
    echo "Unpatch successful, reloading nginx..."
    nginx -s reload
  else
    echo "Unpatch left config invalid, check manually!"
    return 1
  fi
}

status_nginx() {
  if already_patched; then
    echo "Status: CP upload patch is currently APPLIED."
  else
    echo "Status: CP upload patch is NOT applied."
  fi
}

case "$1" in
  patch)   patch_nginx ;;
  unpatch) unpatch_nginx ;;
  status)  status_nginx ;;
  *) echo "Usage: $0 {patch|unpatch|status}" ;;
esac
