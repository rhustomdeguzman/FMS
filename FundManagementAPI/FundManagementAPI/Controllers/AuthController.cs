using FundManagementAPI.Models;
using FundManagementAPI.Repositories;
using Microsoft.AspNetCore.Mvc;
using FundManagementAPI.Services;

namespace FundManagementAPI.Controllers;

[ApiController]
[Route("api/[controller]")]
public sealed class AuthController : ControllerBase
{
    private static readonly HashSet<string> ValidRoles = new(StringComparer.OrdinalIgnoreCase)
    {
        "admin",
        "requestor",
        "department_head",
        "accounting",
        "cashier",
        "custodian"
    };

    private readonly ICashAdvanceRepository _repository;

    public AuthController(ICashAdvanceRepository repository)
    {
        _repository = repository;
    }

    [HttpPost("login")]
    public async Task<ActionResult<LoginResponseDto>> Login(LoginRequest request, CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(request.Username) || string.IsNullOrWhiteSpace(request.Password))
        {
            return BadRequest("Username and password are required.");
        }

        var response = await _repository.LoginAsync(request, cancellationToken);
        return response is null ? Unauthorized("Invalid username or password.") : Ok(response);
    }

    [HttpGet("session")]
    [ResponseCache(NoStore = true, Location = ResponseCacheLocation.None)]
    public ActionResult<LoginResponseDto> Session(
        [FromServices] FineReportSignInService signIn,
        CancellationToken cancellationToken)
    {
        var user = HttpContext.Items["FmsUser"] as AppUserDto;
        return user is null
            ? NotFound()
            : Ok(new LoginResponseDto(user, "SSO login successful."));
    }

    [HttpGet("users")]
    public async Task<ActionResult<IReadOnlyList<AppUserDto>>> GetUsers(
        [FromQuery] bool includeInactive = false,
        CancellationToken cancellationToken = default)
    {
        var users = await _repository.GetAppUsersAsync(includeInactive, cancellationToken);
        return Ok(users);
    }

    [HttpPost("users")]
    public async Task<ActionResult<AppUserDto>> CreateUser(
        CreateAppUserRequest request,
        CancellationToken cancellationToken)
    {
        var validationError = ValidateUserRequest(
            request.AdminUserId,
            request.Username,
            request.DisplayName,
            request.Department,
            request.Role,
            request.Title,
            request.Password,
            request.PettyCashFundAmount,
            requirePassword: true);

        if (validationError is not null)
        {
            return BadRequest(validationError);
        }

        var createdUser = await _repository.CreateAppUserAsync(Normalize(request), cancellationToken);
        return createdUser is null ? BadRequest("Unable to create user.") : Ok(createdUser);
    }

    [HttpPut("users/{userId:int}")]
    public async Task<ActionResult<AppUserDto>> UpdateUser(
        int userId,
        UpdateAppUserRequest request,
        CancellationToken cancellationToken)
    {
        if (userId <= 0)
        {
            return BadRequest("User is required.");
        }

        var validationError = ValidateUserRequest(
            request.AdminUserId,
            request.Username,
            request.DisplayName,
            request.Department,
            request.Role,
            request.Title,
            request.Password,
            request.PettyCashFundAmount,
            requirePassword: false);

        if (validationError is not null)
        {
            return BadRequest(validationError);
        }

        var updatedUser = await _repository.UpdateAppUserAsync(userId, Normalize(request), cancellationToken);
        return updatedUser is null ? NotFound("User was not found.") : Ok(updatedUser);
    }

    [HttpPut("users/{userId:int}/custodian-fund")]
    public async Task<ActionResult<AppUserDto>> UpdateCustodianFund(
        int userId,
        UpdateCustodianFundRequest request,
        CancellationToken cancellationToken)
    {
        if (userId <= 0)
        {
            return BadRequest("Custodian user is required.");
        }

        if (request.AdminUserId <= 0)
        {
            return BadRequest("Admin user is required.");
        }

        if (request.PettyCashFundAmount <= 0)
        {
            return BadRequest("Custodian initial fund must be greater than zero.");
        }

        var updatedUser = await _repository.UpdateCustodianFundAsync(userId, request, cancellationToken);
        return updatedUser is null ? NotFound("Custodian user was not found.") : Ok(updatedUser);
    }

    [HttpGet("department-custodians")]
    public async Task<ActionResult<IReadOnlyList<DepartmentCustodianAssignmentDto>>> GetDepartmentCustodians(
        CancellationToken cancellationToken)
    {
        var assignments = await _repository.GetDepartmentCustodianAssignmentsAsync(cancellationToken);
        return Ok(assignments);
    }

    [HttpPut("departments/{departmentCode:int}/custodian")]
    public async Task<ActionResult<DepartmentCustodianAssignmentDto>> UpdateDepartmentCustodian(
        int departmentCode,
        UpdateDepartmentCustodianRequest request,
        CancellationToken cancellationToken)
    {
        if (departmentCode <= 0)
        {
            return BadRequest("Department is required.");
        }

        if (request.AdminUserId <= 0)
        {
            return BadRequest("Admin user is required.");
        }

        if (request.CustodianUserId <= 0)
        {
            return BadRequest("Custodian user is required.");
        }

        var updatedAssignment = await _repository.UpdateDepartmentCustodianAssignmentAsync(
            departmentCode,
            request,
            cancellationToken);

        return updatedAssignment is null ? NotFound("Department was not found.") : Ok(updatedAssignment);
    }

    private static string? ValidateUserRequest(
        int adminUserId,
        string username,
        string displayName,
        string department,
        string role,
        string title,
        string? password,
        decimal? pettyCashFundAmount,
        bool requirePassword)
    {
        if (adminUserId <= 0)
        {
            return "Admin user is required.";
        }

        if (string.IsNullOrWhiteSpace(username) ||
            string.IsNullOrWhiteSpace(displayName) ||
            string.IsNullOrWhiteSpace(department) ||
            string.IsNullOrWhiteSpace(role) ||
            string.IsNullOrWhiteSpace(title))
        {
            return "Username, display name, department, and title are required.";
        }

        if (requirePassword && string.IsNullOrWhiteSpace(password))
        {
            return "Password is required.";
        }

        var normalizedRole = NormalizeRole(role);
        if (!ValidRoles.Contains(normalizedRole))
        {
            return "Role is not valid.";
        }

        if (string.Equals(normalizedRole, "custodian", StringComparison.OrdinalIgnoreCase) &&
            (!pettyCashFundAmount.HasValue || pettyCashFundAmount.Value <= 0))
        {
            return "Custodian initial fund must be greater than zero.";
        }

        return null;
    }

    private static CreateAppUserRequest Normalize(CreateAppUserRequest request)
    {
        var role = NormalizeRole(request.Role);

        return request with
        {
            Username = request.Username.Trim(),
            DisplayName = request.DisplayName.Trim(),
            Department = request.Department.Trim(),
            Role = role,
            Title = request.Title.Trim(),
            Password = request.Password.Trim()
        };
    }

    private static UpdateAppUserRequest Normalize(UpdateAppUserRequest request)
    {
        var role = NormalizeRole(request.Role);

        return request with
        {
            Username = request.Username.Trim(),
            DisplayName = request.DisplayName.Trim(),
            Department = request.Department.Trim(),
            Role = role,
            Title = request.Title.Trim(),
            Password = string.IsNullOrWhiteSpace(request.Password) ? null : request.Password.Trim()
        };
    }

    private static string NormalizeRole(string role)
    {
        var roleAlias = role.Trim().Replace('_', ' ').Replace('-', ' ').ToLowerInvariant();

        return roleAlias switch
        {
            "admin" or "administrator" or "system admin" or "system administrator" => "admin",
            "requestor" or "requester" or "requestor user" or "requester user" => "requestor",
            "department head" or "department approver" or "dept head" or "depthead" or "approver" => "department_head",
            "accounting" or "accounting reviewer" or "accounts payable" or "account payable" or "ap" => "accounting",
            "cashier" => "cashier",
            "custodian" or "petty cash custodian" => "custodian",
            _ => roleAlias
        };
    }

    private static string NormalizeTitle(string role, string title) =>
        role switch
        {
            "admin" => "Administrator",
            "requestor" => "Requestor",
            "department_head" => "Department Head",
            "accounting" => "Accounting Reviewer",
            "cashier" => "Cashier",
            "custodian" => "Petty Cash Custodian",
            _ => title.Trim()
        };
}
