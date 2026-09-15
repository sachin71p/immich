import { Body, Controller, Delete, Get, HttpCode, HttpStatus, Param, Patch, Post, Put } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import type { AuthDto } from 'src/dtos/auth.dto.js';
import { Endpoint, HistoryBuilder } from 'src/decorators.js';
import {
  SharedSpaceCreateDto,
  SharedSpaceMemberResponseDto,
  SharedSpaceMembersDto,
  SharedSpaceOwnerDto,
  SharedSpaceResponseDto,
  SharedSpaceTimelineDto,
  SharedSpaceUpdateDto,
} from 'src/dtos/shared-space.dto.js';
import { ApiTag, Permission } from 'src/enum.js';
import { Auth, Authenticated } from 'src/middleware/auth.guard.js';
import { SharedSpaceService } from 'src/services/shared-space.service.js';
import { UUIDParamDto } from 'src/validation.js';

// fork: shared-libraries
@ApiTags(ApiTag.SharedSpaces)
@Controller('shared-spaces')
export class SharedSpaceController {
  constructor(private service: SharedSpaceService) {}

  @Post()
  @Authenticated({ permission: Permission.SharedSpaceCreate })
  @Endpoint({ summary: 'Create a shared space', history: new HistoryBuilder().added('v3') })
  create(@Auth() auth: AuthDto, @Body() dto: SharedSpaceCreateDto): Promise<SharedSpaceResponseDto> {
    return this.service.create(auth, dto);
  }

  @Get()
  @Authenticated({ permission: Permission.SharedSpaceRead })
  @Endpoint({ summary: 'List my shared spaces', history: new HistoryBuilder().added('v3') })
  getAll(@Auth() auth: AuthDto): Promise<SharedSpaceResponseDto[]> {
    return this.service.getAll(auth);
  }

  @Get(':id')
  @Authenticated({ permission: Permission.SharedSpaceRead })
  @Endpoint({ summary: 'Get a shared space', history: new HistoryBuilder().added('v3') })
  get(@Auth() auth: AuthDto, @Param() { id }: UUIDParamDto): Promise<SharedSpaceResponseDto> {
    return this.service.get(auth, id);
  }

  @Patch(':id')
  @Authenticated({ permission: Permission.SharedSpaceUpdate })
  @Endpoint({ summary: 'Update a shared space', history: new HistoryBuilder().added('v3') })
  update(
    @Auth() auth: AuthDto,
    @Param() { id }: UUIDParamDto,
    @Body() dto: SharedSpaceUpdateDto,
  ): Promise<SharedSpaceResponseDto> {
    return this.service.update(auth, id, dto);
  }

  @Delete(':id')
  @Authenticated({ permission: Permission.SharedSpaceDelete })
  @HttpCode(HttpStatus.NO_CONTENT)
  @Endpoint({ summary: 'Delete a shared space', history: new HistoryBuilder().added('v3') })
  delete(@Auth() auth: AuthDto, @Param() { id }: UUIDParamDto): Promise<void> {
    return this.service.delete(auth, id);
  }

  @Get(':id/members')
  @Authenticated({ permission: Permission.SharedSpaceRead })
  @Endpoint({ summary: 'List shared-space members', history: new HistoryBuilder().added('v3') })
  getMembers(@Auth() auth: AuthDto, @Param() { id }: UUIDParamDto): Promise<SharedSpaceMemberResponseDto[]> {
    return this.service.getMembers(auth, id);
  }

  @Post(':id/members')
  @Authenticated({ permission: Permission.SharedSpaceMemberCreate })
  @HttpCode(HttpStatus.NO_CONTENT)
  @Endpoint({ summary: 'Add shared-space members', history: new HistoryBuilder().added('v3') })
  addMembers(@Auth() auth: AuthDto, @Param() { id }: UUIDParamDto, @Body() dto: SharedSpaceMembersDto): Promise<void> {
    return this.service.addMembers(auth, id, dto);
  }

  @Delete(':id/members/:userId')
  @Authenticated({ permission: Permission.SharedSpaceMemberDelete })
  @HttpCode(HttpStatus.NO_CONTENT)
  @Endpoint({ summary: 'Remove a shared-space member', history: new HistoryBuilder().added('v3') })
  removeMember(@Auth() auth: AuthDto, @Param() { id }: UUIDParamDto, @Param('userId') userId: string): Promise<void> {
    return this.service.removeMember(auth, id, userId);
  }

  @Put(':id/owner')
  @Authenticated({ permission: Permission.SharedSpaceMemberUpdate })
  @HttpCode(HttpStatus.NO_CONTENT)
  @Endpoint({ summary: 'Transfer shared-space ownership', history: new HistoryBuilder().added('v3') })
  transferOwner(@Auth() auth: AuthDto, @Param() { id }: UUIDParamDto, @Body() dto: SharedSpaceOwnerDto): Promise<void> {
    return this.service.transferOwner(auth, id, dto);
  }

  @Patch(':id/members/me')
  @Authenticated({ permission: Permission.SharedSpaceMemberUpdate })
  @HttpCode(HttpStatus.NO_CONTENT)
  @Endpoint({ summary: 'Update my shared-space settings', history: new HistoryBuilder().added('v3') })
  updateMyTimeline(
    @Auth() auth: AuthDto,
    @Param() { id }: UUIDParamDto,
    @Body() dto: SharedSpaceTimelineDto,
  ): Promise<void> {
    return this.service.updateMyTimeline(auth, id, dto);
  }
}
