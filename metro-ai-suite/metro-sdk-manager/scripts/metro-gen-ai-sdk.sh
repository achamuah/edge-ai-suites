#!/bin/bash

#######################################
# Metro Gen AI SDK System Resource Checker and Installation Script
# Checks CPU, Memory, Storage, and Intel GPU resources
# Installs Docker, Docker Compose, and required container images
# Globals:
#   None
# Arguments:
#   --skip-system-check: Skip system resource check
#   --skip-docker: Skip Docker installation
#   --skip-images: Skip Docker image download
#   --help: Show help message
# Outputs:
#   System resource information and installation status to stdout
#######################################


  # Array of repositories to clone: "url|branch|directory"
  repositories=(
    "https://github.com/open-edge-platform/edge-ai-libraries|v1.2.0|edge-ai-libraries"
    "https://github.com/open-edge-platform/edge-ai-suites|v1.2.0|edge-ai-suites"
  )
  
  images=(
    "intel/audio-analyzer:1.2.1"
    "intel/document-ingestion:1.2.1"
    "intel/multimodal-embedding-serving:1.2.1"
    "intel/vdms-dataprep:1.2.1"
    "intel/vlm-openvino-serving:1.2.1"
  )

set -euo pipefail

readonly SCRIPT_NAME="$(basename "${0}")"
readonly LOG_PREFIX="[${SCRIPT_NAME}]"

# Color definitions
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[0;37m'
readonly BOLD='\033[1m'
readonly NC='\033[0m' # No Color

#######################################
# Print error message to stderr and exit
# Arguments:
#   Error message
#######################################
err() {
  echo -e "${RED}${LOG_PREFIX} ERROR: ${*}${NC}" >&2
  exit 1
}

#######################################
# Print info message to stdout
# Arguments:
#   Info message
#######################################
info() {
  echo -e "${BLUE}${LOG_PREFIX} INFO: ${*}${NC}"
}

#######################################
# Print success message to stdout
# Arguments:
#   Success message
#######################################
success() {
  echo -e "${GREEN}${LOG_PREFIX} SUCCESS: ${*}${NC}"
}

#######################################
# Print warning message to stdout
# Arguments:
#   Warning message
#######################################
warn() {
  echo -e "${YELLOW}${LOG_PREFIX} WARNING: ${*}${NC}"
}

#######################################
# Check if command exists
# Arguments:
#   Command name
# Returns:
#   0 if command exists, 1 otherwise
#######################################
command_exists() {
  command -v "${1}" >/dev/null 2>&1
}

#######################################
# Get CPU information
# Outputs:
#   CPU model and core count
#######################################
get_cpu_info() {
  local cpu_model
  local cpu_cores
  
  if [[ -r /proc/cpuinfo ]]; then
    # Temporarily disable pipefail for these commands
    set +o pipefail
    cpu_model=$(grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | sed 's/^ *//' 2>/dev/null)
    cpu_cores=$(nproc 2>/dev/null)
    set -o pipefail
    
    if [[ -n "${cpu_model}" && -n "${cpu_cores}" ]]; then
      echo -e "${GREEN}${BOLD}CPU:${NC} ${CYAN}${cpu_model}${NC} ${YELLOW}(${cpu_cores} cores)${NC}"
    else
      echo -e "${GREEN}${BOLD}CPU:${NC} ${RED}Information not available${NC}"
    fi
  else
    echo -e "${GREEN}${BOLD}CPU:${NC} ${RED}Information not available${NC}"
  fi
}

#######################################
# Get memory information
# Outputs:
#   Total and available memory in GB
#######################################
get_memory_info() {
  local total_mem
  local avail_mem
  
  if [[ -r /proc/meminfo ]]; then
    set +o pipefail
    total_mem=$(awk '/MemTotal/ {printf "%.1f", $2/1024/1024}' /proc/meminfo 2>/dev/null)
    avail_mem=$(awk '/MemAvailable/ {printf "%.1f", $2/1024/1024}' /proc/meminfo 2>/dev/null)
    set -o pipefail
    
    if [[ -n "${total_mem}" && -n "${avail_mem}" ]]; then
      echo -e "${GREEN}${BOLD}Memory:${NC} ${CYAN}${avail_mem}GB available${NC} ${WHITE}/${NC} ${MAGENTA}${total_mem}GB total${NC}"
    else
      echo -e "${GREEN}${BOLD}Memory:${NC} ${RED}Information not available${NC}"
    fi
  else
    echo -e "${GREEN}${BOLD}Memory:${NC} ${RED}Information not available${NC}"
  fi
}

#######################################
# Get storage information
# Outputs:
#   Root filesystem usage
#######################################
get_storage_info() {
  local storage_info
  
  if command_exists "df"; then
    set +o pipefail
    storage_info=$(df -h / | awk 'NR==2 {printf "%s used / %s total (%s available)", $3, $2, $4}' 2>/dev/null)
    set -o pipefail
    
    if [[ -n "${storage_info}" ]]; then
      # Parse storage info components
      local used=$(echo "${storage_info}" | awk '{print $1}')
      local total=$(echo "${storage_info}" | awk '{print $4}')
      local available=$(echo "${storage_info}" | awk '{print $6}' | tr -d '()')
      echo -e "${GREEN}${BOLD}Storage:${NC} ${YELLOW}${used} used${NC} ${WHITE}/${NC} ${MAGENTA}${total} total${NC} ${WHITE}(${CYAN}${available} available${WHITE})${NC}"
    else
      echo -e "${GREEN}${BOLD}Storage:${NC} ${RED}Information not available${NC}"
    fi
  else
    echo -e "${GREEN}${BOLD}Storage:${NC} ${RED}Information not available${NC}"
  fi
}

#######################################
# Get Intel GPU information
# Outputs:
#   Intel GPU details if available
#######################################
get_intel_gpu_info() {
  local gpu_info=""
  
  # Check for Intel GPU using lspci
  if command_exists "lspci"; then
    set +o pipefail
    gpu_info=$(lspci | grep -i "vga\|display\|3d" | grep -i intel | head -1 2>/dev/null)
    set -o pipefail
    
    if [[ -n "${gpu_info}" ]]; then
      echo -e "${GREEN}${BOLD}Intel GPU:${NC} ${MAGENTA}${gpu_info##*: }${NC}"
    else
      echo -e "${GREEN}${BOLD}Intel GPU:${NC} ${RED}Not detected${NC}"
    fi
  elif command_exists "lshw"; then
    set +o pipefail
    gpu_info=$(lshw -c display 2>/dev/null | grep -i intel -A 5 | grep "product:" | head -1 2>/dev/null)
    set -o pipefail
    
    if [[ -n "${gpu_info}" ]]; then
      echo -e "${GREEN}${BOLD}Intel GPU:${NC} ${MAGENTA}${gpu_info##*: }${NC}"
    else
      echo -e "${GREEN}${BOLD}Intel GPU:${NC} ${RED}Not detected${NC}"
    fi
  else
    echo -e "${GREEN}${BOLD}Intel GPU:${NC} ${RED}Cannot detect (lspci/lshw not available)${NC}"
  fi
  
  # Check for Intel GPU tools
  if command_exists "intel_gpu_top"; then
    echo -e "${GREEN}${BOLD}Intel GPU Tools:${NC} ${CYAN}intel_gpu_top available${NC}"
  elif [[ -d /sys/class/drm/card0 ]]; then
    echo -e "${GREEN}${BOLD}Intel GPU Tools:${NC} ${CYAN}DRM interface available${NC}"
  fi
}

#######################################
# Check Docker installation and version
# Outputs:
#   Docker version information or installation status
#######################################
check_docker_installation() {
  echo -e "${GREEN}${BOLD}Docker Status:${NC}"
  
  if command_exists "docker"; then
    local docker_version
    set +o pipefail
    docker_version=$(docker --version 2>/dev/null | cut -d' ' -f3 | tr -d ',')
    set -o pipefail
    
    if [[ -n "${docker_version}" ]]; then
      echo -e "  ${CYAN}✓ Docker installed${NC} ${WHITE}(${docker_version})${NC}"
      
      # Check if Docker is running
      if docker info >/dev/null 2>&1; then
        echo -e "  ${CYAN}✓ Docker service is running${NC}"
      else
        warn "Docker is installed but service is not running"
        echo -e "  ${YELLOW}Starting Docker service...${NC}"
        sudo systemctl start docker || err "Failed to start Docker service"
        sudo systemctl enable docker || warn "Failed to enable Docker service on boot"
      fi
    else
      warn "Docker command found but version check failed"
      return 1
    fi
  else
    warn "Docker is not installed"
    return 1
  fi
}

#######################################
# Install Docker and Docker Compose
# Installs Docker CE and Docker Compose if not present
#######################################
install_docker() {
  info "Installing Docker and Docker Compose..."
  
  # Update package list
  info "Updating package list..."
  sudo apt-get update || err "Failed to update package list"
  
  # Install prerequisites
  info "Installing prerequisites..."
  sudo apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release || err "Failed to install prerequisites"
  
  # Add Docker's official GPG key
  info "Adding Docker's GPG key..."
  sudo mkdir -p /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg || err "Failed to add Docker GPG key"
  
  # Add Docker repository
  info "Adding Docker repository..."
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null || err "Failed to add Docker repository"
  
  # Update package list again
  sudo apt-get update || err "Failed to update package list after adding Docker repository"
  
  # Install Docker Engine
  info "Installing Docker Engine..."
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || err "Failed to install Docker"
  
  # Add current user to docker group
  info "Adding user to docker group..."
  sudo usermod -aG docker $USER || warn "Failed to add user to docker group"
  
  # Start and enable Docker
  sudo systemctl start docker || err "Failed to start Docker service"
  sudo systemctl enable docker || warn "Failed to enable Docker service on boot"
  
  success "Docker installation completed successfully!"
  warn "Please log out and log back in for group changes to take effect, or run 'newgrp docker'"
}

#######################################
# Check Docker Compose installation
# Outputs:
#   Docker Compose version or installation status
#######################################
check_docker_compose() {
  echo -e "${GREEN}${BOLD}Docker Compose Status:${NC}"
  
  if command_exists "docker" && docker compose version >/dev/null 2>&1; then
    local compose_version
    set +o pipefail
    compose_version=$(docker compose version 2>/dev/null | grep -o 'v[0-9]\+\.[0-9]\+\.[0-9]\+' | head -1)
    set -o pipefail
    
    if [[ -n "${compose_version}" ]]; then
      echo -e "  ${CYAN}✓ Docker Compose installed${NC} ${WHITE}(${compose_version})${NC}"
    else
      echo -e "  ${CYAN}✓ Docker Compose available${NC}"
    fi
  else
    warn "Docker Compose is not available"
    return 1
  fi
}

#######################################
# Pull required Docker images
# Downloads OpenVINO and DLStreamer images
#######################################
pull_required_images() {
  info "Pulling required Docker images..."
  echo -e "${GREEN}${BOLD}Container Images:${NC}"
  
  for image in "${images[@]}"; do
    echo -e "  ${YELLOW}Pulling ${image}...${NC}"
    if docker pull "${image}" >/dev/null 2>&1; then
      echo -e "  ${CYAN}✓ ${image}${NC}"
    else
      warn "Failed to pull ${image}"
    fi
  done
  
  success "Docker image pull completed!"
}

#######################################
# Verify Docker images
# Lists the pulled images for verification
#######################################
verify_images() {
  echo -e "${GREEN}${BOLD}Installed Images:${NC}"
  
  for image in "${images[@]}"; do
    set +o pipefail
    local image_info=$(docker images --format "{{.Repository}}:{{.Tag}}" | grep "^${image}" | head -1)
    set -o pipefail
    
    if [[ -n "${image_info}" ]]; then
      echo -e "  ${CYAN}✓ ${image_info}${NC}"
    else
      echo -e "  ${RED}✗ ${image} not found${NC}"
    fi
  done
}

#######################################
# Create metro directory if it doesn't exist
# Returns:
#   0 if directory exists or was created successfully
#######################################
create_metro_directory() {
  local metro_dir="$HOME/metro"
  
  if [[ ! -d "${metro_dir}" ]]; then
    info "Creating metro directory at ${metro_dir}..."
    mkdir -p "${metro_dir}" || err "Failed to create metro directory"
    success "Metro directory created successfully"
  else
    info "Metro directory already exists at ${metro_dir}"
  fi
  
  echo -e "${GREEN}${BOLD}Metro Directory:${NC} ${CYAN}${metro_dir}${NC}"
}

#######################################
# Clone git repository
# Arguments:
#   Repository URL
#   Branch name
#   Target directory name
#######################################
clone_repository() {
  local repo_url="$1"
  local branch="$2"
  local target_dir="$3"
  local metro_dir="$HOME/metro"
  local full_path="${metro_dir}/${target_dir}"
  
  if [[ -d "${full_path}" ]]; then
    warn "Directory ${target_dir} already exists, checking if it's the correct repository..."
    
    # Check if it's a git repository and has the correct remote
    if [[ -d "${full_path}/.git" ]]; then
      local current_remote
      set +o pipefail
      current_remote=$(cd "${full_path}" && git remote get-url origin 2>/dev/null)
      set -o pipefail
      
      if [[ "${current_remote}" == "${repo_url}" ]]; then
        info "Repository ${target_dir} already exists, updating to branch ${branch}..."
        
        # Update the repository
        (cd "${full_path}" && git fetch origin && git checkout "${branch}" && git pull origin "${branch}") >/dev/null 2>&1 || {
          warn "Failed to update repository, removing and re-cloning..."
          rm -rf "${full_path}"
          clone_repository "$1" "$2" "$3"
          return $?
        }
        
        success "Repository ${target_dir} updated to branch ${branch}"
        return 0
      else
        warn "Directory ${target_dir} exists but points to different repository, removing..."
        rm -rf "${full_path}"
      fi
    else
      warn "Directory ${target_dir} exists but is not a git repository, removing..."
      rm -rf "${full_path}"
    fi
  fi
  
  # Clone the repository
  info "Cloning ${repo_url} (branch: ${branch}) to ${target_dir}..."
  
  if git clone --branch "${branch}" "${repo_url}" "${full_path}" >/dev/null 2>&1; then
    success "Successfully cloned ${target_dir}"
    echo -e "  ${CYAN}✓ ${target_dir} (branch: ${branch})${NC}"
  else
    warn "Failed to clone ${repo_url}"
    echo -e "  ${RED}✗ ${target_dir} (failed)${NC}"
  fi
}

#######################################
# Clone required repositories
# Clones repositories from the predefined list
#######################################
clone_repositories() {
  info "Cloning required repositories..."
  echo -e "${GREEN}${BOLD}Git Repositories:${NC}"
  
  # Check if git is installed, install if not available
  if ! command_exists "git"; then
    info "Git is not installed. Installing git..."
    sudo apt-get update || err "Failed to update package list"
    sudo apt-get install -y git || err "Failed to install git"
    success "Git installed successfully!"
  fi
  
  # Clone each repository
  for repo in "${repositories[@]}"; do
    IFS='|' read -r repo_url branch target_dir <<< "${repo}"
    clone_repository "${repo_url}" "${branch}" "${target_dir}"
  done
}

#######################################
# Verify Git Repositories
# Lists the cloned repositories for verification
#######################################
verify_repos() {
  echo -e "${GREEN}${BOLD}Installed Repos:${NC}"

  for repo in "${repositories[@]}"; do
    IFS='|' read -r repo_url branch target_dir <<< "${repo}"
    new_target_dir="$HOME/metro/${target_dir}"
    local repo_info=$(git -C "${new_target_dir}" remote get-url origin 2>/dev/null)

    if [[ -n "${repo_info}" ]]; then
      echo -e "  ${CYAN}✓ ${target_dir}${NC}"
    else
      echo -e "  ${RED}✗ ${target_dir} not found${NC}"
    fi
  done
}

#######################################
# Show help message
#######################################
show_help() {
  echo -e "${BOLD}${CYAN}Metro Gen AI SDK Installation Script${NC}"
  echo ""
  echo -e "${BOLD}Usage:${NC} $0 [OPTIONS]"
  echo ""
  echo -e "${BOLD}Options:${NC}"
  echo -e "  ${GREEN}--skip-system-check${NC}    Skip system resource verification"
  echo -e "  ${GREEN}--skip-docker${NC}          Skip Docker installation check"
  echo -e "  ${GREEN}--skip-images${NC}          Skip Docker image download"
  echo -e "  ${GREEN}--skip-git-clone${NC}       Skip git repository cloning"
  echo -e "  ${GREEN}--help${NC}                 Show this help message"
  echo ""
  echo -e "${BOLD}Examples:${NC}"
  echo -e "  $0                           # Full installation"
  echo -e "  $0 --skip-system-check       # Skip hardware check"
  echo -e "  $0 --skip-docker             # Only do system check and images"
  echo ""
}

#######################################
# Main function
#######################################
main() {
  local skip_system_check=false
  local skip_docker=false
  local skip_images=false
  local skip_git_clone=false
  
  # Parse command line arguments
  while [[ $# -gt 0 ]]; do
    case $1 in
      --skip-system-check)
        skip_system_check=true
        shift
        ;;
      --skip-docker)
        skip_docker=true
        shift
        ;;
      --skip-images)
        skip_images=true
        shift
        ;;
      --skip-git-clone)
        skip_git_clone=true
        shift
        ;;
      --help)
        show_help
        exit 0
        ;;
      *)
        err "Unknown option: $1. Use --help for usage information."
        ;;
    esac
  done
  info "Metro Gen AI SDK Installation Script"
  echo -e "${BOLD}${BLUE}==================================================${NC}"
  
  # System Requirements Check
  if [[ "${skip_system_check}" != "true" ]]; then
    echo -e "${BOLD}${CYAN}System Requirements Check${NC}"
    echo -e "${BOLD}${BLUE}==================================================${NC}"
    
    get_cpu_info
    get_memory_info
    get_storage_info
    get_intel_gpu_info
    
    echo -e "${BOLD}${BLUE}==================================================${NC}"
  else
    info "Skipping system requirements check"
  fi
  
  # Docker Installation and Setup
  if [[ "${skip_docker}" != "true" ]]; then
    echo -e "${BOLD}${CYAN}Docker Installation and Setup${NC}"
    echo -e "${BOLD}${BLUE}==================================================${NC}"
    
    # Check Docker installation
    if ! check_docker_installation; then
      info "Docker not found. Installing Docker..."
      install_docker
      
      # Verify installation
      if check_docker_installation; then
        success "Docker installation verified!"
      else
        err "Docker installation failed or verification unsuccessful"
      fi
    fi
    
    # Check Docker Compose
    if ! check_docker_compose; then
      warn "Docker Compose not available. This is included with modern Docker installations."
    fi
    
    echo -e "${BOLD}${BLUE}==================================================${NC}"
  else
    info "Skipping Docker installation check"
    # Still need to verify Docker is available for image pulling
    if [[ "${skip_images}" != "true" ]] && ! command_exists "docker"; then
      err "Docker is required for image operations but was skipped. Please install Docker first."
    fi
  fi
  
  # Container Image Setup
  if [[ "${skip_images}" != "true" ]]; then
    echo -e "${BOLD}${CYAN}Container Image Setup${NC}"
    echo -e "${BOLD}${BLUE}==================================================${NC}"
    
    # Pull required images
    pull_required_images
    
    echo ""
    echo -e "${BOLD}${BLUE}==================================================${NC}"
  else
    info "Skipping Docker image download"
  fi
  
  # Git Repository Setup
  if [[ "${skip_git_clone}" != "true" ]]; then
    echo -e "${BOLD}${CYAN}Git Repository Setup${NC}"
    echo -e "${BOLD}${BLUE}==================================================${NC}"
    
    # Create metro directory
    create_metro_directory
    
    echo ""
    # Clone required repositories
    clone_repositories
    
    echo -e "${BOLD}${BLUE}==================================================${NC}"
  else
    info "Skipping git repository cloning"
  fi




  # Container Image Setup
  if [[ "${skip_images}" != "true" ]]; then
      verify_images
  fi
  
  # Git Repository Setup
  if [[ "${skip_git_clone}" != "true" ]]; then
    verify_repos
  fi
  
  echo -e "${BOLD}${BLUE}==================================================${NC}"
  success "Metro Gen AI SDK installation completed successfully!"
  echo -e "${BOLD}${BLUE}==================================================${NC}"
  
  echo ""
  info "Next steps:"
  info "1. Navigate to ${HOME}/metro/ to explore the cloned repositories"
  info "2. Check repository documentation for usage instructions"
  info "3. Start developing with Metro Gen AI SDK!"

}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "${@}"
fi
