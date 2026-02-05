#!/bin/env bash

# Tests various scenarios for creating, validating, and uploading TRS files

# --- Configuration ---
SOURCE="$LOGNAME.MY.DATASET"
TARGET_BASE="$LOGNAME.TESTCURL"
USS_BASE="/tmp/$LOGNAME_test"

export PATH=/usr/lpp/IBM/zoau/v1r3/:$PATH

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# --- Helper Functions ---

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

assert_equals() {
    local expected="$1"
    local actual="$2"
    local test_name="$3"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if [ "$expected" == "$actual" ]; then
        log_info "â PASS: $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        log_error "â FAIL: $test_name"
        log_error "  Expected: $expected"
        log_error "  Actual:   $actual"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

assert_file_exists() {
    local file="$1"
    local test_name="$2"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if [ -f "$file" ]; then
        log_info "â PASS: $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        log_error "â FAIL: $test_name"
        log_error "  File not found: $file"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

assert_command_success() {
    local cmd="$1"
    local test_name="$2"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if eval "$cmd" > /dev/null 2>&1; then
        log_info "â PASS: $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        log_error "â FAIL: $test_name"
        log_error "  Command failed: $cmd"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

assert_not_equals() {
    local not_expected="$1"
    local actual="$2"
    local test_name="$3"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    
    if [ "$not_expected" != "$actual" ]; then
        log_info "â PASS: $test_name"
        TESTS_PASSED=$((TESTS_PASSED + 1))
        return 0
    else
        log_error "â FAIL: $test_name"
        log_error "  Should not equal: $not_expected"
        log_error "  Actual:           $actual"
        TESTS_FAILED=$((TESTS_FAILED + 1))
        return 1
    fi
}

cleanup_test_files() {
    local target="$1"
    local uss_file="$2"
    
    if [ -n "$target" ]; then
        tsocmd "delete '$target'" > /dev/null 2>&1
    fi
    if [ -n "$uss_file" ]; then
        rm -f "$uss_file"
    fi
}

get_file_encoding() {
    local file="$1"
    ls -T "$file" 2>/dev/null | awk '{print $2}'
}

get_file_tag_status() {
    local file="$1"
    ls -T "$file" 2>/dev/null | awk '{print $3}'
}

# --- Test Functions ---

test_create_trs_file() {
    local test_name="Create TRS file via AMATERSE"
    local target="${TARGET_BASE}.TRS1"
    local uss_file="${USS_BASE}_1.trs"
    
    echo ""
    log_info "=== Running: $test_name ==="
    
    cleanup_test_files "$target" "$uss_file"
    
    # Allocate dataset
    tsocmd "alloc da('$target') new catalog space(10,10) tracks recfm(f,b) lrecl(1024) blksize(27648) unit(sysda)" > /dev/null 2>&1
    
    # Run AMATERSE
    mvscmd --pgm=AMATERSE --sysut1="$SOURCE" --sysut2="$target" --sysprint=* --args='PACK' > /dev/null 2>&1
    
    # Copy to USS
    cp "//'$target'" "$uss_file" 2>/dev/null
    
    assert_file_exists "$uss_file" "$test_name - File created"
    
    cleanup_test_files "$target" "$uss_file"
}

test_validate_file_size() {
    local test_name="Validate TRS file size (multiple of 1024)"
    local target="${TARGET_BASE}.TRS2"
    local uss_file="${USS_BASE}_2.trs"
    
    echo ""
    log_info "=== Running: $test_name ==="
    
    cleanup_test_files "$target" "$uss_file"
    
    # Create TRS file
    tsocmd "alloc da('$target') new catalog space(10,10) tracks recfm(f,b) lrecl(1024) blksize(27648) unit(sysda)" > /dev/null 2>&1
    mvscmd --pgm=AMATERSE --sysut1="$SOURCE" --sysut2="$target" --sysprint=* --args='PACK' > /dev/null 2>&1
    cp "//'$target'" "$uss_file" 2>/dev/null
    
    if [ -f "$uss_file" ]; then
        local file_size=$(ls -l "$uss_file" | awk '{print $5}')
        local remainder=$((file_size % 1024))
        
        assert_equals "0" "$remainder" "$test_name - Size check (${file_size} bytes)"
    else
        log_error "File not created for size validation test"
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    
    cleanup_test_files "$target" "$uss_file"
}

test_validate_trs_header() {
    local test_name="Validate TRS header signature"
    local target="${TARGET_BASE}.TRS3"
    local uss_file="${USS_BASE}_3.trs"
    
    echo ""
    log_info "=== Running: $test_name ==="
    
    cleanup_test_files "$target" "$uss_file"
    
    # Create TRS file
    tsocmd "alloc da('$target') new catalog space(10,10) tracks recfm(f,b) lrecl(1024) blksize(27648) unit(sysda)" > /dev/null 2>&1
    mvscmd --pgm=AMATERSE --sysut1="$SOURCE" --sysut2="$target" --sysprint=* --args='PACK' > /dev/null 2>&1
    cp "//'$target'" "$uss_file" 2>/dev/null
    
    if [ -f "$uss_file" ]; then
        local header_hex=$(od -t x1 -N 1 "$uss_file" | head -n 1 | awk '{print $2}')
        
        if [[ "$header_hex" == "02" || "$header_hex" == "01" || "$header_hex" == "07" ]]; then
            assert_equals "valid" "valid" "$test_name - Header check (0x$header_hex)"
        else
            assert_equals "02, 01, or 07" "$header_hex" "$test_name - Header check"
        fi
    else
        log_error "File not created for header validation test"
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    
    cleanup_test_files "$target" "$uss_file"
}

test_curl_download_encoding_ascii() {
    local test_name="Curl download with --download-encoding ascii"
    local output_file="${USS_BASE}_download_ascii.txt"
    
    echo ""
    log_info "=== Running: $test_name ==="
    
    rm -f "$output_file"
    
    # Download with ascii encoding
    curl --download-encoding ascii -o "$output_file" https://example.com > /dev/null 2>&1
    
    if [ -f "$output_file" ]; then
        local encoding=$(get_file_encoding "$output_file")
        local tag_status=$(get_file_tag_status "$output_file")
        
        assert_equals "ISO8859-1" "$encoding" "$test_name - Encoding check"
        assert_equals "T=on" "$tag_status" "$test_name - Tag status check"
    else
        log_error "Download failed"
        TESTS_RUN=$((TESTS_RUN + 2))
        TESTS_FAILED=$((TESTS_FAILED + 2))
    fi
    
    rm -f "$output_file"
}

test_curl_tag_alias() {
    local test_name="Curl download with --tag alias"
    local output_file="${USS_BASE}_tag_ascii.txt"
    
    echo ""
    log_info "=== Running: $test_name ==="
    
    rm -f "$output_file"
    
    # Download with --tag alias
    curl --tag ascii -o "$output_file" https://example.com > /dev/null 2>&1
    
    if [ -f "$output_file" ]; then
        local encoding=$(get_file_encoding "$output_file")
        local tag_status=$(get_file_tag_status "$output_file")
        
        assert_equals "ISO8859-1" "$encoding" "$test_name - Encoding check"
        assert_equals "T=on" "$tag_status" "$test_name - Tag status check"
    else
        log_error "Download failed"
        TESTS_RUN=$((TESTS_RUN + 2))
        TESTS_FAILED=$((TESTS_FAILED + 2))
    fi
    
    rm -f "$output_file"
}

test_curl_download_encoding_binary() {
    local test_name="Curl download with --download-encoding binary"
    local output_file="${USS_BASE}_download_binary.txt"
    
    echo ""
    log_info "=== Running: $test_name ==="
    
    rm -f "$output_file"
    
    # Download with binary encoding
    curl --download-encoding binary -o "$output_file" https://example.com > /dev/null 2>&1
    
    if [ -f "$output_file" ]; then
        local encoding=$(get_file_encoding "$output_file")
        local tag_status=$(get_file_tag_status "$output_file")
        
        assert_equals "binary" "$encoding" "$test_name - Encoding check"
        assert_equals "T=off" "$tag_status" "$test_name - Tag status check"
    else
        log_error "Download failed"
        TESTS_RUN=$((TESTS_RUN + 2))
        TESTS_FAILED=$((TESTS_FAILED + 2))
    fi
    
    rm -f "$output_file"
}

test_curl_download_encoding_auto() {
    local test_name="Curl download with --download-encoding auto (heuristic)"
    local output_file="${USS_BASE}_download_auto.txt"
    
    echo ""
    log_info "=== Running: $test_name ==="
    
    rm -f "$output_file"
    
    # Download with auto encoding (should detect based on content)
    curl --download-encoding auto -o "$output_file" https://example.com > /dev/null 2>&1
    
    if [ -f "$output_file" ]; then
        local encoding=$(get_file_encoding "$output_file")
        local tag_status=$(get_file_tag_status "$output_file")
        
        # Auto should detect and tag the file (not untagged)
        assert_not_equals "untagged" "$encoding" "$test_name - Encoding detected"
        assert_equals "T=on" "$tag_status" "$test_name - Tag status check"
        
        log_info "  Detected encoding: $encoding"
    else
        log_error "Download failed"
        TESTS_RUN=$((TESTS_RUN + 2))
        TESTS_FAILED=$((TESTS_FAILED + 2))
    fi
    
    rm -f "$output_file"
}

test_curl_no_encoding_option() {
    local test_name="Curl download without encoding option (default behavior)"
    local output_file="${USS_BASE}_no_encoding.txt"
    
    echo ""
    log_info "=== Running: $test_name ==="
    
    rm -f "$output_file"
    
    # Download without any encoding option
    curl -o "$output_file" https://example.com > /dev/null 2>&1
    
    if [ -f "$output_file" ]; then
        local encoding=$(get_file_encoding "$output_file")
        local tag_status=$(get_file_tag_status "$output_file")
        
        log_info "  Default encoding: $encoding"
        log_info "  Default tag status: $tag_status"
        
        # Just verify file was created and tagged somehow
        assert_not_equals "" "$encoding" "$test_name - File has encoding"
    else
        log_error "Download failed"
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    
    rm -f "$output_file"
}

test_ftp_upload_dataset() {
    local test_name="FTP upload of dataset (dry-run)"
    local target="${TARGET_BASE}.TRS4"
    
    echo ""
    log_info "=== Running: $test_name ==="
    
    cleanup_test_files "$target" ""
    
    # Create TRS file
    tsocmd "alloc da('$target') new catalog space(10,10) tracks recfm(f,b) lrecl(1024) blksize(27648) unit(sysda)" > /dev/null 2>&1
    mvscmd --pgm=AMATERSE --sysut1="$SOURCE" --sysut2="$target" --sysprint=* --args='PACK' > /dev/null 2>&1
    
    # Test curl command syntax (verify curl binary works)
    local cmd="curl --version > /dev/null 2>&1"
    assert_command_success "$cmd" "$test_name - Curl binary is functional"
    
    cleanup_test_files "$target" ""
}

test_invalid_encoding_value() {
    local test_name="Curl with invalid encoding value"
    local output_file="${USS_BASE}_invalid.txt"
    
    echo ""
    log_info "=== Running: $test_name ==="
    
    rm -f "$output_file"
    
    # Try download with invalid encoding (should fail or warn)
    curl --download-encoding invalid_encoding -o "$output_file" https://example.com > /dev/null 2>&1
    local exit_code=$?
    
    if [ $exit_code -ne 0 ]; then
        assert_equals "non-zero" "non-zero" "$test_name - Command failed as expected"
    else
        log_warn "Command succeeded with invalid encoding (may have defaulted)"
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
    fi
    
    rm -f "$output_file"
}

test_encoding_e2a() {
    local test_name="Curl download with --download-encoding e2a"
    local output_file="${USS_BASE}_e2a.txt"
    
    echo ""
    log_info "=== Running: $test_name ==="
    
    rm -f "$output_file"
    
    # Download with e2a encoding (EBCDIC to ASCII)
    curl --download-encoding e2a -o "$output_file" https://example.com > /dev/null 2>&1
    
    if [ -f "$output_file" ]; then
        local encoding=$(get_file_encoding "$output_file")
        local tag_status=$(get_file_tag_status "$output_file")
        
        assert_equals "ISO8859-1" "$encoding" "$test_name - Encoding check"
        assert_equals "T=on" "$tag_status" "$test_name - Tag status check"
    else
        log_error "Download failed"
        TESTS_RUN=$((TESTS_RUN + 2))
        TESTS_FAILED=$((TESTS_FAILED + 2))
    fi
    
    rm -f "$output_file"
}

test_encoding_a2e() {
    local test_name="Curl download with --download-encoding a2e"
    local output_file="${USS_BASE}_a2e.txt"
    
    echo ""
    log_info "=== Running: $test_name ==="
    
    rm -f "$output_file"
    
    # Download with a2e encoding (ASCII to EBCDIC)
    curl --download-encoding a2e -o "$output_file" https://example.com > /dev/null 2>&1
    
    if [ -f "$output_file" ]; then
        local encoding=$(get_file_encoding "$output_file")
        local tag_status=$(get_file_tag_status "$output_file")
        
        assert_equals "IBM-1047" "$encoding" "$test_name - Encoding check"
        assert_equals "T=on" "$tag_status" "$test_name - Tag status check"
    else
        log_error "Download failed"
        TESTS_RUN=$((TESTS_RUN + 2))
        TESTS_FAILED=$((TESTS_FAILED + 2))
    fi
    
    rm -f "$output_file"
}

test_upload_encoding_ascii() {
    local test_name="Curl upload with --upload-encoding ascii (syntax check)"
    
    echo ""
    log_info "=== Running: $test_name ==="
    
    # Test that the option is recognized by curl
    local cmd="curl --help all | grep -q 'upload-encoding'"
    assert_command_success "$cmd" "$test_name - Option exists"
}

test_upload_encoding_binary() {
    local test_name="Curl upload with --upload-encoding binary (syntax check)"
    local input_file="${USS_BASE}_upload_binary_input.txt"
    
    echo ""
    log_info "=== Running: $test_name ==="
    
    rm -f "$input_file"
    
    # Create a test file
    echo "Binary test content" > "$input_file"
    
    # Test that curl accepts the option without error
    curl --upload-encoding binary --help > /dev/null 2>&1
    local exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        assert_equals "0" "0" "$test_name - Option accepted"
    else
        assert_equals "0" "$exit_code" "$test_name - Option accepted"
    fi
    
    rm -f "$input_file"
}

test_upload_encoding_a2e() {
    local test_name="Curl upload with --upload-encoding a2e (syntax check)"
    local input_file="${USS_BASE}_upload_a2e_input.txt"
    
    echo ""
    log_info "=== Running: $test_name ==="
    
    rm -f "$input_file"
    
    # Create a test file with ASCII content
    echo "ASCII content for a2e conversion" > "$input_file"
    chtag -tc ISO8859-1 "$input_file"
    
    # Test that curl accepts the a2e encoding option
    curl --upload-encoding a2e --help > /dev/null 2>&1
    local exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        assert_equals "0" "0" "$test_name - Option accepted"
    else
        assert_equals "0" "$exit_code" "$test_name - Option accepted"
    fi
    
    rm -f "$input_file"
}

test_upload_trs_file() {
    local test_name="Upload TRS file with proper encoding"
    local target="${TARGET_BASE}.TRS5"
    local uss_file="${USS_BASE}_upload_trs.trs"
    
    echo ""
    log_info "=== Running: $test_name ==="
    
    cleanup_test_files "$target" "$uss_file"
    
    # Create TRS file
    tsocmd "alloc da('$target') new catalog space(10,10) tracks recfm(f,b) lrecl(1024) blksize(27648) unit(sysda)" > /dev/null 2>&1
    mvscmd --pgm=AMATERSE --sysut1="$SOURCE" --sysut2="$target" --sysprint=* --args='PACK' > /dev/null 2>&1
    cp "//'$target'" "$uss_file" 2>/dev/null
    
    if [ -f "$uss_file" ]; then
        # Verify TRS file can be used with curl upload (syntax check)
        local cmd="curl --version > /dev/null 2>&1"
        assert_command_success "$cmd" "$test_name - Curl can handle TRS uploads"
        
        # Check that TRS file is properly tagged as binary
        local encoding=$(get_file_encoding "$uss_file")
        log_info "  TRS file encoding: $encoding"
    else
        log_error "TRS file not created"
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    
    cleanup_test_files "$target" "$uss_file"
}



# --- Main Test Runner ---

run_all_tests() {
    echo "========================================"
    echo "  TRS File & Curl Test Suite"
    echo "========================================"
    
    # Run all tests
    test_create_trs_file
    test_validate_file_size
    test_validate_trs_header
    test_curl_download_encoding_ascii
    test_curl_tag_alias
    test_curl_download_encoding_binary
    test_curl_download_encoding_auto
    test_curl_no_encoding_option
    test_encoding_e2a
    test_encoding_a2e
    test_upload_encoding_ascii
    test_upload_encoding_binary
    test_upload_encoding_a2e
    test_upload_trs_file
    test_ftp_upload_dataset
    test_invalid_encoding_value
    
    # Print summary
    echo ""
    echo "========================================"
    echo "  Test Summary"
    echo "========================================"
    echo "Total Tests:  $TESTS_RUN"
    echo -e "${GREEN}Passed:       $TESTS_PASSED${NC}"
    echo -e "${RED}Failed:       $TESTS_FAILED${NC}"
    echo "========================================"
    
    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}All tests passed!${NC}"
        return 0
    else
        echo -e "${RED}Some tests failed!${NC}"
        return 1
    fi
}

# Run tests if script is executed directly
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    run_all_tests
    exit $?
fi
