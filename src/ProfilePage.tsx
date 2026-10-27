import { BellRing, Copy, LockKeyhole, ShieldCheck, Trash2, Users } from 'lucide-react'

type Member = { user_id: string; display_name: string; role: string; joined_at?: string }

type Props = {
  name: string
  email: string
  role: string
  teamName: string
  inviteCode: string
  members: Member[]
  isAdmin: boolean
  currentUserId: string
  sessionActive: boolean
  pushSupported: boolean
  pushPermission: string
  pushSubscribed: boolean
  pushBusy: boolean
  onTogglePush: () => void
  onCopyInvite: () => void
  onRemoveMember: (member: Member) => void
  onChangeRole: (member: Member, role: 'admin' | 'member') => void
}

export default function ProfilePage({ name, email, role, teamName, inviteCode, members, isAdmin, currentUserId, sessionActive, pushSupported, pushPermission, pushSubscribed, pushBusy, onTogglePush, onCopyInvite, onRemoveMember, onChangeRole }: Props) {
  return <div className="content profile-content">
    <div className="page-heading">
      <div><div className="eyebrow">MY ACCOUNT</div><h1>{isAdmin ? '관리자 페이지' : '마이페이지'}</h1><p>내 계정 정보와 팀 공간 정보를 확인할 수 있어요.</p></div>
    </div>

    <section className="panel profile-summary">
      <div className="profile-summary-heading"><div className="avatar self profile-avatar">{name.slice(0, 1)}</div><div><h2>{name}</h2><span>{role === 'admin' ? '관리자' : '팀원'}</span></div></div>
      <div className="profile-fields">
        <div><small>이메일</small><b>{email || '이메일 정보 없음'}</b></div>
        <div><small>소속 팀</small><b>{teamName}</b></div>
        <div><small>권한</small><b>{role === 'admin' ? '관리자' : '팀원'}</b></div>
      </div>
    </section>

    <section className="panel profile-settings-card">
      <div className="panel-heading"><div><h3>로그인 및 알림 설정</h3><p>이 기기에서 로그인 상태와 출퇴근 알림을 관리합니다.</p></div></div>
      <div className="profile-setting-row">
        <span className="profile-setting-icon"><LockKeyhole size={17}/></span>
        <div className="profile-setting-copy"><b>로그인 유지</b><small>{email || '로그인 계정'} · 이 기기의 앱 저장소에 로그인 상태를 보관하고 자동 갱신합니다.</small></div>
        <span className="profile-setting-status is-on">{sessionActive ? '유지 중' : '로그인 필요'}</span>
      </div>
      <div className="profile-setting-row">
        <span className="profile-setting-icon"><BellRing size={17}/></span>
        <div className="profile-setting-copy"><b>팀 활동 푸시 알림</b><small>{!pushSupported ? '이 브라우저는 푸시 알림을 지원하지 않습니다. 지원되는 브라우저에서 이용해 주세요.' : pushPermission === 'denied' ? '기기에서 알림 권한이 차단되어 있어요. 브라우저 또는 휴대폰 설정에서 허용해 주세요.' : '팀 활동의 출퇴근 인증·퇴근 보고·수정 요청을 이 기기로 푸시 전송합니다. 받을 각 기기에서 따로 켜 주세요.'}</small></div>
        <span className={`profile-setting-status ${pushSubscribed ? 'is-on' : ''}`}>{pushSubscribed ? '켜짐' : pushPermission === 'denied' ? '권한 차단' : '꺼짐'}</span>
        <button className={`button ${pushSubscribed ? 'outline' : 'primary'} small profile-push-toggle`} onClick={onTogglePush} disabled={!pushSupported || pushBusy || !sessionActive}>{pushBusy ? '처리 중…' : pushSubscribed ? '알림 끄기' : '알림 켜기'}</button>
      </div>
      <p className="profile-note">푸시가 오지 않으면 기기 알림 권한과 집중 모드를 확인해 주세요. iPhone은 홈 화면에 추가한 앱을 열어 알림을 허용해야 합니다. 알림은 이 기기에만 연결되므로 다른 팀원도 각자 설정해야 해요.</p>
    </section>

    {isAdmin && <>
      <section className="panel invite-admin-card">
        <div><span className="profile-section-icon"><Users size={17}/></span><div><h2>팀원 초대</h2><p>초대 코드를 새 팀원에게 전달해 주세요. 가입 후 코드로 팀에 합류할 수 있어요.</p></div></div>
        <code>{inviteCode || '초대 코드 없음'}</code>
        <button className="button primary" onClick={onCopyInvite} disabled={!inviteCode}><Copy size={15}/> 초대 코드 복사</button>
      </section>

      <section className="panel team-admin-panel">
        <div className="panel-heading"><div><h3>현재 팀원</h3><p>{members.length}명이 팀 공간을 함께 사용하고 있어요.</p></div><ShieldCheck size={18}/></div>
        <div className="managed-member-list">{members.map(member => <article className="managed-member" key={member.user_id}>
          <div className="avatar">{member.display_name.slice(0, 1)}</div>
          <div className="managed-member-info"><b>{member.display_name}{member.user_id === currentUserId && <em>나</em>}</b><small>{member.role === 'admin' ? '관리자' : '팀원'}</small></div>
          {member.user_id === currentUserId ? <span className="managed-role">내 관리자 권한</span> : <div className="managed-member-actions"><select className="role-select" aria-label={`${member.display_name} 권한`} value={member.role} onChange={event => onChangeRole(member, event.target.value as 'admin' | 'member')}><option value="member">팀원</option><option value="admin">관리자</option></select><button className="button outline small remove-member" onClick={() => onRemoveMember(member)}><Trash2 size={14}/> 내보내기</button></div>}
        </article>)}</div>
        <p className="profile-note">팀원을 내보내면 해당 계정은 이 팀 공간에 다시 초대받기 전까지 접근할 수 없습니다. 업무 기록은 유지됩니다.</p>
      </section>
    </>}
  </div>
}
